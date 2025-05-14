from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import torch
from transformers import AutoTokenizer, AutoModelForCausalLM
from peft import PeftModel
import os
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI()

# 環境変数からモデル名、LoRAアダプター名、Hugging Faceトークンを取得
MODEL_NAME = os.getenv("HF_MODEL_NAME", "google/gemma-2-2b-jpn-it")
LORA_ADAPTER_NAME = os.getenv("LORA_ADAPTER_NAME", None)
HF_TOKEN = os.getenv("HF_TOKEN", None)

if not HF_TOKEN:
    logger.warning(f"Hugging Face token (HF_TOKEN) is not set. Downloads may fail if {MODEL_NAME} is a gated model.")

model = None
tokenizer = None
model_loaded_time = 0

class GenerationRequest(BaseModel):
    prompt: str
    max_new_tokens: int = 150

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
        tokenizer = AutoTokenizer.from_pretrained(MODEL_ID, token=HF_TOKEN) # MODEL_ID を使うように修正
        logger.info("Tokenizer loaded successfully.")

        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        logger.info(f"Using device: {device}")

        logger.info(f"Loading base model {MODEL_ID}...") # MODEL_ID を使うように修正
        base_model = AutoModelForCausalLM.from_pretrained(
            MODEL_ID, # MODEL_ID を使うように修正
            device_map="auto" if device.type == 'cuda' else {"": "cpu"},
            torch_dtype=torch.bfloat16 if device.type == 'cuda' else torch.float32,
            token=HF_TOKEN
        )
        logger.info("Base model loaded successfully.")

        if LORA_ADAPTER_NAME and LORA_ADAPTER_NAME.strip():
            logger.info(f"Loading LoRA adapter {LORA_ADAPTER_NAME} for {MODEL_NAME}...")
            try:
                model = PeftModel.from_pretrained(base_model, LORA_ADAPTER_NAME, token=HF_TOKEN)
                logger.info(f"LoRA adapter {LORA_ADAPTER_NAME} loaded successfully.")
            except Exception as e:
                logger.error(f"Failed to load LoRA adapter {LORA_ADAPTER_NAME}: {e}. Proceeding with the base model only.")
                model = base_model
        else:
            logger.info(f"No LoRA adapter specified or LORA_ADAPTER_NAME is empty. Using base model: {MODEL_NAME}.")
            model = base_model

        model.eval() # 推論モードに設定

        tokenizer.pad_token = tokenizer.eos_token
        tokenizer.padding_side = "right"

        model_loaded_time = round((time.time() - start_time) * 1000)
        logger.info(f"Model and tokenizer loaded in {model_loaded_time} ms.")

        logger.info("Performing a quick test inference on startup...")
        try:
            test_messages = [{"role": "user", "content": "日本の首都はどこですか？"}]
            test_inputs = tokenizer.apply_chat_template(
                test_messages,
                return_tensors="pt",
                add_generation_prompt=True,
                return_dict=True
            ).to(model.device)
            
            test_outputs = model.generate(**test_inputs, max_new_tokens=50, pad_token_id=tokenizer.eos_token_id)
            test_generated_text = tokenizer.batch_decode(test_outputs[:, test_inputs['input_ids'].shape[1]:], skip_special_tokens=True)[0]
            logger.info(f"Test inference successful: {test_generated_text.strip()}")
        except Exception as e:
            logger.error(f"Test inference failed: {e}")

    except Exception as e:
        logger.error(f"Error loading model on startup: {e}")
        raise RuntimeError(f"Failed to load model: {e}")


@app.post("/generate", response_model=GenerationResponse)
async def generate_text(request: GenerationRequest):
    if not model or not tokenizer:
        raise HTTPException(status_code=503, detail="Model or tokenizer not loaded yet. Please wait or check logs.")
    
    start_time = time.time()
    try:
        messages = [{"role": "user", "content": request.prompt}]
        inputs = tokenizer.apply_chat_template(
            messages,
            return_tensors="pt",
            add_generation_prompt=True,
            return_dict=True
        ).to(model.device)

        logger.info(f"Generating text for prompt (first 50 chars): '{request.prompt[:50]}...' with max_new_tokens: {request.max_new_tokens}")
        with torch.no_grad():
            outputs = model.generate(
                **inputs,
                max_new_tokens=request.max_new_tokens,
                pad_token_id=tokenizer.eos_token_id,
                do_sample=True,
                temperature=0.8,
            )
        generated_text = tokenizer.batch_decode(outputs[:, inputs['input_ids'].shape[1]:], skip_special_tokens=True)[0]
        processing_time_ms = round((time.time() - start_time) * 1000)
        logger.info(f"Generated text (first 100 chars): '{generated_text[:100]}...' in {processing_time_ms} ms.")
        
        current_model_name = MODEL_NAME
        if LORA_ADAPTER_NAME and LORA_ADAPTER_NAME.strip():
             current_model_name = f"{MODEL_NAME} + {LORA_ADAPTER_NAME}"

        return GenerationResponse(
            generated_text=generated_text.strip(),
            model_name=current_model_name,
            processing_time_ms=processing_time_ms
            )
            
    except Exception as e:
        logger.error(f"Error during text generation: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health_check():
    if model and tokenizer:
        try:
            _ = model.device 
            return {"status": "healthy", "model_name": MODEL_NAME, "model_loaded_ms": model_loaded_time, "device": str(model.device)}
        except Exception as e:
            logger.error(f"Health check failed due to model access: {e}")
            return {"status": "unhealthy", "model_name": MODEL_NAME, "error": str(e)}
    return {"status": "unhealthy", "model_name": MODEL_NAME, "detail": "Model or tokenizer not loaded."}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080, log_level="info")