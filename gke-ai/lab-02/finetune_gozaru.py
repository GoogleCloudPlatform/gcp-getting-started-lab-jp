import os, sys, logging, torch
from datasets import load_dataset
from transformers import AutoModelForCausalLM, AutoTokenizer
from peft import LoraConfig, PeftModel
from trl import SFTConfig, SFTTrainer
from huggingface_hub import HfApi

# ---------- 0. 環境変数チェック ----------
HF_TOKEN    = os.getenv("HF_TOKEN")
HF_USERNAME = os.getenv("HF_USERNAME")
MODEL_ID    = os.getenv("HF_MODEL_NAME", "google/gemma-3-4b-it")
REPO_NAME   = os.getenv("LORA_ADAPTER_REPO_NAME", "gemma-gozaru-adapter")

if not HF_TOKEN or not HF_USERNAME:
    sys.stderr.write("ERROR: HF_TOKEN / HF_USERNAME を export してください\n")
    sys.exit(1)

# ---------- 1. ロギング ----------
logging.basicConfig(
    format="%(asctime)s %(levelname)s:%(name)s: %(message)s",
    level=logging.INFO,
)
log = logging.getLogger(__name__)
log.info(f"Base Model : {MODEL_ID}")
log.info(f"Adapter Repo: {HF_USERNAME}/{REPO_NAME}")

# ---------- 2. データセット ----------
log.info("▶ データセット読み込み …")
ds = load_dataset(
    "bbz662bbz/databricks-dolly-15k-ja-gozaru",
    split="train",
    token=HF_TOKEN,
)
ds = ds.filter(lambda x: x["category"] == "open_qa").train_test_split(test_size=0.1)
train_ds, eval_ds = ds["train"], ds["test"]

# ---------- 3. モデル & トークナイザー ----------
dtype = (
    torch.bfloat16
    if torch.cuda.is_available() and torch.cuda.get_device_capability()[0] >= 8
    else torch.float16
)
model = AutoModelForCausalLM.from_pretrained(
    MODEL_ID,
    torch_dtype=dtype,
    attn_implementation="eager",
    device_map="auto",
)
tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)
tokenizer.pad_token = tokenizer.eos_token           # Gemma 固定
model.config.use_cache = False                      # gradient_checkpointing と両立

# ---------- 4. LoRA Config ----------
peft_conf = LoraConfig(
    r=16,
    lora_alpha=16,
    lora_dropout=0.1,
    target_modules="all-linear",        # Gemma3 は Linear に自動マッチ
    task_type="CAUSAL_LM",
    modules_to_save=["lm_head", "embed_tokens"],
)

# ---------- 5. prompt 生成関数 ----------
def to_chat(example):
    """
    Gemma chat_template を用いて user/model 2 turn に整形
    """
    msgs = [
        {"role": "user",  "content": example["instruction"]},
        {"role": "model", "content": example["output"]},
    ]
    return {
        "text": tokenizer.apply_chat_template(
            msgs,
            tokenize=False,
            add_generation_prompt=True,     # 公式推奨: <end_of_turn> を付ける
        )
    }

log.info("▶ prompt 変換 …")
train_ds = train_ds.map(to_chat, remove_columns=train_ds.column_names, desc="train->text")
eval_ds  = eval_ds.map(to_chat,  remove_columns=eval_ds.column_names,  desc="eval->text")

# ---------- 6. SFTConfig ----------
sft_cfg = SFTConfig(
    output_dir=REPO_NAME,
    max_length=512,                 # TRL 0.17.0 は max_length
    packing=True,
    num_train_epochs=3,
    per_device_train_batch_size=1,
    gradient_accumulation_steps=4,
    gradient_checkpointing=True,
    logging_steps=10,
    save_strategy="epoch",
    learning_rate=2e-4,
    fp16=(dtype == torch.float16),
    bf16=(dtype == torch.bfloat16),
    max_grad_norm=0.3,
    warmup_ratio=0.03,
    lr_scheduler_type="constant",
    push_to_hub=True,
    hub_model_id=f"{HF_USERNAME}/{REPO_NAME}",
    hub_token=HF_TOKEN,
    dataset_text_field="text",
)

# ---------- 7. Trainer ----------
log.info("▶ SFTTrainer 構築 …")
trainer = SFTTrainer(
    model,
    train_dataset=train_ds,
    eval_dataset=eval_ds,
    args=sft_cfg,
    peft_config=peft_conf,
    # tokenizer 引数は 0.17.0 に存在しない
)

# ---------- 8. 学習 ----------
log.info("▶ ファインチューニング開始")
trainer.train()

# ---------- 9. アダプタ保存 & Push ----------
log.info("▶ アダプタ保存")
trainer.save_model()                        # REPO_NAME 内に adapter_config.json + adapter_model.bin

# ---------- 10. マージ (任意) ----------
log.info("▶ LoRA とベースモデルをマージ …")
merged_dir = f"{sft_cfg.output_dir}_merged"
merged = PeftModel.from_pretrained(model, sft_cfg.output_dir).merge_and_unload()
merged.save_pretrained(merged_dir, safe_serialization=True)
tokenizer.save_pretrained(merged_dir)

# log.info("▶ Hub へ push")
# api = HfApi()
# api.upload_folder(
#     folder_path=merged_dir,
#     repo_id=f"{HF_USERNAME}/{REPO_NAME}-merged",
#     repo_type="model",
#     token=HF_TOKEN,
# )

log.info("=== 完了 ===")
