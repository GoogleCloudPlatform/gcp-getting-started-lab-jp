import os
import torch
from datasets import load_dataset, Dataset
from transformers import AutoTokenizer, AutoModelForCausalLM, TrainingArguments
from peft import LoraConfig, prepare_model_for_kbit_training, PeftModel
from trl import SFTTrainer
import logging
from huggingface_hub import HfApi

# ロギング設定
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# 環境変数から設定を取得
MODEL_ID = os.getenv("HF_MODEL_NAME", "google/gemma-2-2b-jpn-it")
HF_TOKEN = os.getenv("HF_TOKEN")
HF_USERNAME = os.getenv("HF_USERNAME")
LORA_ADAPTER_REPO_NAME = os.getenv("LORA_ADAPTER_REPO_NAME", "my-gemma-gozaru-adapter") # デフォルト名

if not HF_TOKEN or not HF_USERNAME:
    logger.error("HF_TOKEN and HF_USERNAME environment variables must be set for fine-tuning and pushing to Hub.")
    exit(1)

OUTPUT_DIR = f"./{LORA_ADAPTER_REPO_NAME}" # 学習結果のローカル保存ディレクトリ
FINAL_REPO_ID = f"{HF_USERNAME}/{LORA_ADAPTER_REPO_NAME}" # Hugging Face Hub の最終リポジトリID

logger.info(f"Fine-tuning model: {MODEL_ID}")
logger.info(f"LoRA adapter will be saved to: {FINAL_REPO_ID}")

# --- 1. データセットの準備 ---
logger.info("データセットを準備中...")
# 日本語「ござる」データセットを読み込み
dataset = load_dataset("bbz662bbz/databricks-dolly-15k-ja-gozaru", split="train", token=HF_TOKEN)
# open_qa カテゴリのみにフィルタリング
dataset = dataset.filter(lambda example: example["category"] == "open_qa")

# データセットをプロンプト形式に変換する関数の定義
def generate_prompt(example):
    return f"<bos><start_of_turn>user\n{example['instruction']}<end_of_turn>\n<start_of_turn>model\n{example['output']}<eos>"

# textカラムの追加
def add_text(example):
    example["text"] = generate_prompt(example)
    return example

dataset = dataset.map(add_text)
dataset = dataset.remove_columns(["input", "category", "output", "index", "instruction"])

# データセットを学習用と評価用に分割
train_test_split = dataset.train_test_split(test_size=0.1)
train_dataset = train_test_split["train"]
eval_dataset = train_test_split["test"]
logger.info(f"学習データセットサイズ: {len(train_dataset)}")
logger.info(f"評価データセットサイズ: {len(eval_dataset)}")
logger.info(f"学習データセットの最初の例:\n{train_dataset[0]['text']}")

# --- 2. トークナイザーとモデルの読み込み ---
logger.info(f"トークナイザーとベースモデル {MODEL_ID} を読み込み中...")
tokenizer = AutoTokenizer.from_pretrained(MODEL_ID, token=HF_TOKEN)

# GPU が利用可能なら bf16 でロード
torch_dtype = torch.bfloat16 if torch.cuda.is_available() else torch.float32
device_map = "auto" if torch.cuda.is_available() else {"": "cpu"}

model = AutoModelForCausalLM.from_pretrained(
    MODEL_ID,
    device_map=device_map,
    torch_dtype=torch_dtype,
    token=HF_TOKEN,
)
logger.info("モデルとトークナイザーの読み込み完了。")

# 警告を回避するためトークナイザーのパディング方向を右側に設定
tokenizer.padding_side = 'right'
if tokenizer.pad_token is None:
    tokenizer.pad_token = tokenizer.eos_token

# モデルをk-bitトレーニング用に準備 (PEFTでメモリ効率を上げるため)
model = prepare_model_for_kbit_training(model)

# --- 3. LoRA の設定 ---
logger.info("LoRA 設定を定義中...")
peft_config = LoraConfig(
    lora_alpha=32,
    lora_dropout=0.1,
    r=8,
    bias="none",
    target_modules=["q_proj", "o_proj", "k_proj", "v_proj", "gate_proj", "up_proj", "down_proj"],
    task_type="CAUSAL_LM",
)
logger.info("LoRA 設定定義完了。")

# --- 4. ハイパーパラメータの設定 ---
logger.info("トレーニング引数を設定中...")
args = TrainingArguments(
    output_dir=OUTPUT_DIR,                   # モデルを保存するディレクトリ
    num_train_epochs=3,                      # 学習エポック数
    per_device_train_batch_size=1,           # デバイスごとの学習バッチサイズ
    gradient_accumulation_steps=2,           # 勾配蓄積ステップ数
    gradient_checkpointing=True,             # メモリ節約のために勾配チェックポイントを使用
    optim="adamw_torch_fused",               # 融合AdamWオプティマイザを使用
    logging_steps=10,                        # 10ステップごとにログ出力
    save_strategy="epoch",                   # 各エポック終了時にチェックポイントを保存
    learning_rate=2e-4,                      # 学習率
    bf16=True,                               # 対応GPUがある場合にbfloat16精度を使用
    tf32=True,                               # 対応GPUがある場合にtf32精度を使用
    max_grad_norm=0.3,                       # 最大勾配ノルム
    warmup_ratio=0.03,                       # ウォームアップ比率
    lr_scheduler_type="constant",            # 定数学習率スケジューラを使用
    push_to_hub=True,                        # モデルをHugging Face Hubにプッシュ
    report_to="tensorboard",                 # メトリクスをtensorboardにレポート
    hub_model_id=FINAL_REPO_ID,              # Hugging Face HubのリポジトリID
    hub_token=HF_TOKEN,                      # Hugging Faceトークン
)
logger.info("トレーニング引数設定完了。")

# --- 5. SFTTrainer クラスのインスタンスを作成 ---
logger.info("SFTTrainer を準備中...")
max_seq_length = 1024 # この変数は使用しないが、元のコードに合わせて残しておく
trainer = SFTTrainer(
    model=model,
    args=args,
    train_dataset=train_dataset,
    peft_config=peft_config,
    # max_seq_length=max_seq_length, # ★ここを削除★ (前回削除済み)
    # tokenizer=tokenizer, # ★ここを削除★
    packing=True,
    dataset_text_field="text",
    dataset_kwargs={
        "add_special_tokens": False,
        "append_concat_token": False,
    }
)
logger.info("SFTTrainer 準備完了。")

# --- 6. トレーニングの実行 ---
logger.info("--------------------------------------")
logger.info("ファインチューニングを開始します。")
logger.info("GPUリソースとデータ量に応じて時間がかかります。")
logger.info("--------------------------------------")
trainer.train()
logger.info("--------------------------------------")
logger.info("ファインチューニング完了。")
logger.info("--------------------------------------")

# --- 7. トレーニングが完了したモデルを保存 ---
trainer.save_model()
logger.info(f"LoRA adapter saved locally to {OUTPUT_DIR}")

# 必要に応じて、マージとアップロードを明示的に行う
try:
    logger.info("LoRA adapter とベースモデルをマージ中...")
    merged_model = model.merge_and_unload()
    merged_model_output_dir = f"{OUTPUT_DIR}_merged"
    merged_model.save_pretrained(merged_model_output_dir, safe_serialization=True, max_shard_size="2GB")
    tokenizer.save_pretrained(merged_model_output_dir)
    logger.info(f"マージ済みモデルが {merged_model_output_dir} に保存されました。")

    # マージ済みモデルをHugging Face Hubにプッシュ（オプション）
    api = HfApi()
    logger.info(f"マージ済みモデルをHugging Face Hubにプッシュ中: {FINAL_REPO_ID}-merged...")
    api.upload_folder(
        folder_path=merged_model_output_dir,
        repo_id=f"{FINAL_REPO_ID}-merged",
        repo_type="model",
        token=HF_TOKEN
    )
    logger.info(f"マージ済みモデルが https://huggingface.co/{FINAL_REPO_ID}-merged にプッシュされました。")

except Exception as e:
    logger.error(f"モデルのマージまたはプッシュ中にエラーが発生しました: {e}")

logger.info("すべての処理が完了しました。")
