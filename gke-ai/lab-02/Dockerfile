FROM pytorch/pytorch:2.3.0-cuda12.1-cudnn8-runtime

WORKDIR /app

# 必要なツールをインストール (git は Hugging Face モデルダウンロードに必要)
RUN apt-get update && apt-get install -y \
    git \
    && rm -rf /var/lib/apt/lists/*

# requirements.txt をコピーしてライブラリをインストール
COPY requirements_finetune.txt .
RUN pip install --no-cache-dir -r requirements_finetune.txt

# 学習スクリプトをコピー
COPY finetune_gozaru.py .

# スクリプトを実行可能にする
RUN chmod +x finetune_gozaru.py

# コンテナ起動時に学習スクリプトを実行
ENTRYPOINT ["python3", "finetune_gozaru.py"]
