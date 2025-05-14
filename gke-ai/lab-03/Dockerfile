FROM pytorch/pytorch:2.3.0-cuda12.1-cudnn8-runtime

WORKDIR /app

# 必要なツールをインストール (git は Hugging Face モデルダウンロードに必要)
RUN apt-get update && apt-get install -y \
    git \
    && rm -rf /var/lib/apt/lists/*

# requirements.txtをコピーしてライブラリをインストール
COPY requirements_gozaru.txt .
RUN pip install --no-cache-dir -r requirements_gozaru.txt

# アプリケーションコードをコピー
COPY main_gozaru.py .

# ポート8080を公開
EXPOSE 8080

# アプリケーションの起動コマンド
CMD ["uvicorn", "main_gozaru:app", "--host", "0.0.0.0", "--port", "8080", "--timeout-keep-alive", "60", "--workers", "1"]
