#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Gozaru Gemma Server
  * ベース : google/gemma-3-4b-it
  * LoRA  : tarota0226/gemma-gozaru-adapter   (環境変数で変更可)
"""
import os, time, logging
from typing import List

import torch
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from transformers import AutoTokenizer, AutoModelForCausalLM
from peft import PeftModel

# ───────── ログ設定 ─────────
logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s | %(levelname)7s | %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("gozaru-server")

# ───────── 環境変数 ─────────
MODEL_NAME        = os.getenv("HF_MODEL_NAME", "google/gemma-3-4b-it")
LORA_ADAPTER_NAME = os.getenv("LORA_ADAPTER_NAME")           # 必須
HF_TOKEN          = os.getenv("HF_TOKEN")

if not HF_TOKEN:
    log.warning("HF_TOKEN が未設定です。（公開モデルでなければ失敗します）")

# ───────── FastAPI ─────────
app = FastAPI(title="Gozaru Gemma Server", version="1.0.0")

# ───────── Pydantic ─────────
class GenerationRequest(BaseModel):
    prompt: str
    max_new_tokens: int = Field(150, ge=1, le=1024)
    temperature: float  = Field(0.7, ge=0.0, le=2.0)
    top_p: float        = Field(1.0, ge=0.0, le=1.0)

class GenerationResponse(BaseModel):
    generated_text: str
    model_name: str
    processing_time_ms: int

# ───────── グローバル ─────────
model, tokenizer = None, None
model_loaded_ms  = 0

# ───────── 起動時ロード ────────
@app.on_event("startup")
async def load_model() -> None:
    global model, tokenizer, model_loaded_ms
    t0 = time.time()

    # Tokenizer
    log.info(f"Tokenizer → {MODEL_NAME}")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME, token=HF_TOKEN)
    tokenizer.pad_token, tokenizer.padding_side = tokenizer.eos_token, "right"

    # Device / dtype
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    dtype  = torch.bfloat16 if device.type == "cuda" and torch.cuda.is_bf16_supported() else torch.float32
    log.info(f"Device={device}  dtype={dtype}")

    # Base model
    base_model = AutoModelForCausalLM.from_pretrained(
        MODEL_NAME,
        device_map="auto" if device.type == "cuda" else {"": "cpu"},
        torch_dtype=dtype,
        low_cpu_mem_usage=True,
        token=HF_TOKEN,
    )

    # LoRA
    if not LORA_ADAPTER_NAME:
        raise RuntimeError("LORA_ADAPTER_NAME が未設定です。")
    log.info(f"LoRA adapter → {LORA_ADAPTER_NAME}")
    model = PeftModel.from_pretrained(
        base_model,
        LORA_ADAPTER_NAME,
        device_map="auto",
        torch_dtype=dtype,
        token=HF_TOKEN,
    ).eval()

    model_loaded_ms = int((time.time() - t0) * 1000)
    log.info(f"モデルロード完了 ({model_loaded_ms} ms)")

    # Warm-up (input_ids を位置引数で渡す)
    warm_ids = tokenizer.apply_chat_template(
        [{"role": "user", "content": "拙者の名は？"}],
        return_tensors="pt",
        add_generation_prompt=True,
    ).to(model.device)
    _ = model.generate(warm_ids, max_new_tokens=8, pad_token_id=tokenizer.eos_token_id)
    log.info("Warm-up 完了")

# ───────── 推論エンドポイント ─────────
@app.post("/generate", response_model=GenerationResponse)
async def generate(req: GenerationRequest):
    if model is None:
        raise HTTPException(503, "Model not loaded")

    t0 = time.time()
    try:
        input_ids = tokenizer.apply_chat_template(
            [{"role": "user", "content": req.prompt}],
            return_tensors="pt",
            add_generation_prompt=True,
        ).to(model.device)

        with torch.no_grad():
            outputs = model.generate(
                input_ids,
                max_new_tokens=req.max_new_tokens,
                temperature=req.temperature,
                top_p=req.top_p,
                do_sample=req.temperature > 0.0,
                pad_token_id=tokenizer.eos_token_id,
            )

        prompt_len = input_ids.shape[1]
        generated  = tokenizer.batch_decode(outputs[:, prompt_len:], skip_special_tokens=True)[0]
        elapsed_ms = int((time.time() - t0) * 1000)

        return GenerationResponse(
            generated_text=generated.strip(),
            model_name=f"{MODEL_NAME}+{LORA_ADAPTER_NAME}",
            processing_time_ms=elapsed_ms,
        )

    except Exception as e:
        log.exception("Generation failed")
        raise HTTPException(500, str(e)) from e

# ───────── ヘルスチェック ─────────
@app.get("/health")
async def health():
    try:
        _ = model.device
        return {"status": "healthy", "model": MODEL_NAME, "adapter": LORA_ADAPTER_NAME, "loaded_ms": model_loaded_ms}
    except Exception as e:
        return {"status": "unhealthy", "error": str(e)}

# ───────── 手動起動用 ─────────
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080, log_level="info")