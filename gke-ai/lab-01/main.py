from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import torch
from transformers import AutoTokenizer, AutoModelForCausalLM, BitsAndBytesConfig
from peft import PeftModel
import os
import logging
import time

# ロギング設定
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI()

# 環境変数からモデル名とアダプタ名、Hugging Faceトークンを取得
MODEL_NAME = os.getenv("HF_MODEL_NAME", "google/gemma-3-1b-it")
LORA_ADAPTER_NAME = os.getenv("LORA_ADAPTER_NAME", None) # 設定されていればLoRAをロード
HF_TOKEN = os.getenv("HF_TOKEN", None)

if not HF_TOKEN:
    logger.warning(f"Hugging Face token (HF_TOKEN) is not set. Downloads may fail if {MODEL_NAME} is a gated model.")

model = None
tokenizer = None
model_loaded_time = 0

class GenerationRequest(BaseModel):
    prompt: str
    max_new_tokens: int = 100 # 1Bモデルなので少し短めにデフォルト設定

class GenerationResponse(BaseModel):
    generated_text: str
    model_name: str
    processing_time_ms: int


@app.on_event("startup")
async def load_model_on_startup():
    global model, tokenizer, model_loaded_time
    start_time = time.time()
    try:
        logger.info(f"Loading tokenizer for {MODEL_NAME}...")
        tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME, token=HF_TOKEN)
        logger.info("Tokenizer loaded successfully.")

        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        logger.info(f"Using device: {device}")

        quantization_config = None
        # 1Bモデルでも量子化はメモリ削減に効果的
        if torch.cuda.is_available():
            quantization_config = BitsAndBytesConfig(
                load_in_4bit=True,
                bnb_4bit_quant_type="nf4",
                bnb_4bit_compute_dtype=torch.bfloat16,
                bnb_4bit_use_double_quant=True,
            )
            logger.info("4-bit quantization will be used for the model on GPU.")
        else:
            logger.info("GPU not available, quantization will not be used. Model will run on CPU.")

        logger.info(f"Loading base model {MODEL_NAME}...")
        base_model = AutoModelForCausalLM.from_pretrained(
            MODEL_NAME,
            quantization_config=quantization_config if device.type == 'cuda' else None,
            torch_dtype=torch.bfloat16 if device.type == 'cuda' else torch.float32,
            low_cpu_mem_usage=True,
            device_map="auto" if device.type == 'cuda' else {"": "cpu"},
            token=HF_TOKEN
        )
        logger.info("Base model loaded successfully.")

        if LORA_ADAPTER_NAME and LORA_ADAPTER_NAME.strip():
            logger.info(f"Loading LoRA adapter {LORA_ADAPTER_NAME} for {MODEL_NAME}...")
            try:
                # ベースモデルにLoRAアダプタを適用
                model = PeftModel.from_pretrained(base_model, LORA_ADAPTER_NAME, token=HF_TOKEN)
                # オプション: アダプタをマージして推論を高速化 (VRAM消費は増える可能性)
                # model = model.merge_and_unload()
                # logger.info("LoRA adapter merged successfully.")
                logger.info(f"LoRA adapter {LORA_ADAPTER_NAME} loaded successfully.")
            except Exception as e:
                logger.error(f"Failed to load LoRA adapter {LORA_ADAPTER_NAME}: {e}. Proceeding with the base model only.")
                model = base_model
        else:
            logger.info(f"No LoRA adapter specified or LORA_ADAPTER_NAME is empty. Using base model: {MODEL_NAME}.")
            model = base_model

        model.eval() # 推論モードに設定
        model_loaded_time = round((time.time() - start_time) * 1000)
        logger.info(f"Model and tokenizer loaded in {model_loaded_time} ms.")

        if tokenizer and model:
            logger.info("Performing a quick test inference on startup...")
            try:
                test_prompt = "The capital of Japan is"
                inputs = tokenizer(test_prompt, return_tensors="pt").to(model.device)
                outputs = model.generate(**inputs, max_new_tokens=5, pad_token_id=tokenizer.eos_token_id)
                logger.info(f"Test inference successful: {tokenizer.decode(outputs[0], skip_special_tokens=True)}")
            except Exception as e:
                logger.error(f"Test inference failed: {e}")
        else:
            logger.error("Model or tokenizer not available, skipping test inference.")

    except Exception as e:
        logger.error(f"Error loading model on startup: {e}")
        # ここでエラーが発生すると readinessProbe が失敗し続ける
        raise RuntimeError(f"Failed to load model: {e}")


@app.post("/generate", response_model=GenerationResponse)
async def generate_text(request: GenerationRequest):
    if not model or not tokenizer:
        raise HTTPException(status_code=503, detail="Model or tokenizer not loaded yet. Please wait or check logs.")
    
    start_time = time.time()
    try:
        inputs = tokenizer(request.prompt, return_tensors="pt", truncation=True).to(model.device)
        
        logger.info(f"Generating text for prompt (first 50 chars): '{request.prompt[:50]}...' with max_new_tokens: {request.max_new_tokens}")
        with torch.no_grad():
            outputs = model.generate(
                **inputs,
                max_new_tokens=request.max_new_tokens,
                pad_token_id=tokenizer.eos_token_id, # pad_token_idにeos_token_idを指定
                # repetition_penalty=1.2, # 必要に応じて追加の生成パラメータを設定
                # temperature=0.7,
                # top_k=50,
                # top_p=0.95
            )
        generated_text = tokenizer.decode(outputs[0], skip_special_tokens=True)
        processing_time_ms = round((time.time() - start_time) * 1000)
        logger.info(f"Generated text (first 100 chars): '{generated_text[:100]}...' in {processing_time_ms} ms.")
        
        current_model_name = MODEL_NAME
        if LORA_ADAPTER_NAME and LORA_ADAPTER_NAME.strip() and hasattr(model, 'active_adapter'): # PeftModelの場合
             current_model_name = f"{MODEL_NAME} + {LORA_ADAPTER_NAME}"

        return GenerationResponse(
            generated_text=generated_text,
            model_name=current_model_name,
            processing_time_ms=processing_time_ms
            )
            
    except Exception as e:
        logger.error(f"Error during text generation: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health_check():
    # モデルがロード済みで、基本的な推論が可能であれば healthy とする
    if model and tokenizer:
        try:
            # 簡単なチェック。実際に推論はしないが、モデルオブジェクトが存在するか確認
            # logger.info(f"Health check: Model device: {model.device}")
            return {"status": "healthy", "model_name": MODEL_NAME, "model_loaded_ms": model_loaded_time, "device": str(model.device)}
        except Exception as e:
            logger.error(f"Health check failed: {e}")
            return {"status": "unhealthy", "model_name": MODEL_NAME, "error": str(e)}
    return {"status": "unhealthy", "model_name": MODEL_NAME, "detail": "Model or tokenizer not loaded."}

if __name__ == "__main__":
    import uvicorn
    # UvicornのログレベルをFastAPIのロガーと合わせるか、別途設定
    uvicorn.run(app, host="0.0.0.0", port=8080, log_level="info")
