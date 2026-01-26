<walkthrough-metadata>
  <meta name="title" content="Finetuning with Cloud TPUs" />
  <meta name="description" content="Hands-on tutorial for finetuning a model with Cloud TPUs" />
</walkthrough-metadata>

<walkthrough-disable-features toc></walkthrough-disable-features>

# Cloud TPU によるモデルのファイン チューニング (SFT) 編

## Google Cloud プロジェクトの設定、確認

### **1. 対象の Google Cloud プロジェクトを設定**

ハンズオンを行う Google Cloud プロジェクトのプロジェクト ID とプロジェクト番号を環境変数に設定し、以降の手順で利用できるようにします。 

```bash
export PROJECT_ID=$(gcloud projects list --filter="projectId ~ '^qwiklabs-gcp-' AND projectId != 'qwiklabs-resources'" --format="value(projectId)" | head -n 1)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
echo $PROJECT_ID
echo $PROJECT_NUMBER
```
**Cloud Shell の承認** という確認メッセージが出た場合は **承認** をクリックします。

こちらのような形式で表示されれば、正常に設定されています。（ID と番号自体は環境個別になります）
```
qwiklabs-gcp-01-3c69409e1eb8
180622292206
```

`プロジェクト ID` は [ダッシュボード](https://console.cloud.google.com/home/dashboard) に進み、左上の **プロジェクト情報** から確認します。

## **環境準備**

最初に、ハンズオンを進めるための環境準備を行います。

下記の設定を進めていきます。

- gcloud コマンドラインツール設定
- Google Cloud 機能（API）有効化設定

## **gcloud コマンドラインツール**

Google Cloud は、コマンドライン（CLI）、GUI から操作が可能です。ハンズオンでは主に CLI を使い作業を行いますが、GUI で確認する URL も合わせて掲載します。

### **1. gcloud コマンドラインツールとは?**

gcloud コマンドライン インターフェースは、Google Cloud でメインとなる CLI ツールです。このツールを使用すると、コマンドラインから、またはスクリプトや他の自動化により、多くの一般的なプラットフォーム タスクを実行できます。

たとえば、gcloud CLI を使用して、以下のようなものを作成、管理できます。

- Google Compute Engine 仮想マシン
- Google Kubernetes Engine クラスタ
- Google Cloud SQL インスタンス

**ヒント**: gcloud コマンドラインツールについての詳細は[こちら](https://cloud.google.com/sdk/gcloud?hl=ja)をご参照ください。

### **2. gcloud から利用する Google Cloud のデフォルトプロジェクトを設定**

gcloud コマンドでは操作の対象とするプロジェクトの設定が必要です。操作対象のプロジェクトを設定します。

```bash
gcloud config set project $PROJECT_ID
```

承認するかどうかを聞かれるメッセージがでた場合は、`承認` ボタンをクリックします。

### **3. ハンズオンで利用する Google Cloud の API を有効化する**

Google Cloud では利用したい機能ごとに、有効化を行う必要があります。
ここでは、以降のハンズオンで利用する機能を事前に有効化しておきます。


```bash
gcloud services enable compute.googleapis.com tpu.googleapis.com
```

**GUI**: [API ライブラリ](https://console.cloud.google.com/apis/library?project={{project-id}})

### **4. gcloud コマンドラインツール設定 - リージョン、ゾーン**

コンピュートリソースを作成するデフォルトのリージョン、ゾーンを指定します。

```bash
export REGION="us-west1"
export ZONE="us-west1-c"
gcloud config set compute/region $REGION
gcloud config set compute/zone $ZONE
```

## **参考: Cloud Shell の接続が途切れてしまったときは?**

この手順は今は実行不要です。一定時間非アクティブ状態になる、またはブラウザが固まってしまったなどで `Cloud Shell` が切れてしまう、またはブラウザのリロードが必要になる場合があります。その場合は以下の対応を行い、チュートリアルを再開してください。

### **1. チュートリアル資材があるディレクトリに移動する**

```bash
cd ~/gcp-getting-started-lab-jp/gke-tpu/lab-01
```

### **2. チュートリアルを開く**

```bash
teachme tutorial.md
```
※ `teachme: command not found` と表示される場合は `cloudshell launch-tutorial tutorial.md` を試してみてください。

### **3. Google Cloud への認証を設定する**
Cloud Shellのセッションが切れた場合、Google Cloudへの認証も切れていることがあります。その場合は、以下のコマンドを実行して再認証してください。

```bash
gcloud auth login
```
コマンドを実行すると、Cloud Shell上にURLが表示され、続いて以下のようなメッセージが表示されることがあります。
```
Go to the following link in your browser:

    https://accounts.google.com/o/oauth2/auth?response_type=code&client_id=...

Enable headless account? (Y/n)?
```
ここで、Y を入力して Enter キーを押してください。

その後、Cloud Shell に表示されたURLをコピーします。

**重要: コピーした URL は現在作業しているシークレットウィンドウの新しいタブに貼り付けて開いてください。**

ブラウザで URL を開くと、Google アカウントのログイン画面が表示されます。

アカウント選択の注意:
ハンズオン環境 (例: Qwiklabs) をご利用の場合、通常、student- で始まるメールアドレス (例: student-01-xxxxxxxx@qwiklabs.net) のアカウントを使用するよう指示されているはずです。必ず、その指定された student-アカウントでログインしてください。個人のGmailアカウントなどでログインしないように注意しましょう。

ログインが成功し、許可を求める画面が表示されたら、「許可」または「Allow」をクリックします。
認証が完了すると、ブラウザのタブに認証コードが表示されるか、「You are now authenticated with the Google Cloud SDK!」のようなメッセージが表示されます。その後、Cloud Shellのプロンプトに戻れば、認証は完了です。


### **4. プロジェクト ID とプロジェクト番号を設定する**

```bash
export PROJECT_ID=$(gcloud projects list --filter="projectId ~ '^qwiklabs-gcp-' AND projectId != 'qwiklabs-resources'" --format="value(projectId)" | head -n 1)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
echo $PROJECT_ID
echo $PROJECT_NUMBER
```

### **5. gcloud のデフォルト設定**

```bash
export REGION="us-west1"
export ZONE="us-west1-c"
gcloud config set project $PROJECT_ID
gcloud config set compute/region $REGION
gcloud config set compute/zone $ZONE
```

## **Qwen3 4B モデルのファイン チューニング**

### **1. TPU VM の作成と接続**

このラボでは、ハンズオンの基盤となる TPU を搭載した Compute Engine インスタンスを作成します。
今回は TPU v5e を 8 枚搭載した仮想マシン インスタンスを 1 台作成し、そのインスタンスに SSH で接続した上で SFT (Supervised Fine-Tuning) を実施します。

以下のコマンドを実行してモデル保存用のディスク、および TPU v5e を 8 枚搭載した仮想マシン インスタンスを作成します。インスタンス名は `tpu-v5e-8` とします。

```bash
gcloud compute disks create tpu-data-disk --size 256gb --type pd-balanced

gcloud compute tpus tpu-vm create tpu-v5e-8 \
    --accelerator-type=v5litepod-8 \
    --version=v2-alpha-tpuv5-lite \
    --data-disk source=projects/$PROJECT_ID/zones/us-west1-c/disks/tpu-data-disk
```
※ 仮想マシンがリソース不足などで起動エラーになる場合は `--spot` の引数を追加して再度インスタンス作成を試してみてください。

仮想マシン インスタンスのデプロイには 5 分程度の時間がかかります。コマンドの実行が完了するまでしばらくお待ちください。コマンドが成功すると指定したリージョンに新しい TPU VM インスタンスが作成されます。インスタンスが作成されましたら以下のコマンドで SSH 接続します。

```bash
gcloud compute tpus tpu-vm ssh tpu-v5e-8 --project $PROJECT_ID --zone us-west1-c
```

コマンドを実行すると以下のメッセージが表示される場合があります。表示されたら `Y` と入力し、その後の `Enter passphrase` は何も入力せずに Enter を 2 回押してください。

```
This tool needs to create the directory [/home/student_03_08cc7592871a/.ssh] before being able to generate SSH keys.

Do you want to continue (Y/n)?  Y
```

SSH 接続ができましたら以下のコマンドで事前に作成したディスクをフォーマットし、`/mnt/disks/checkpoints` ディレクトリにマウントします。

```bash
sudo mkfs.ext4 -m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard /dev/sdb
sudo mkdir -p /mnt/disks/checkpoints
sudo mount -o discard,defaults /dev/sdb /mnt/disks/checkpoints
sudo chmod a+w /mnt/disks/checkpoints
```

TPU を搭載した仮想マシン インスタンスへの SSH 接続、ディスクのマウントが完了したら、そのインスタンス上で言語モデルのファイン チューニングを実行します。

## **2. モデル (Qwen 3 4B) の準備**

このハンズオンでは、Hugging Face で公開されている Qwen/Qwen3-4B モデルをファイン チューニングします。まずはモデル名と Hugging Face アクセストークンを環境変数に設定します。

HF_TOKEN の値は、ご自身の Hugging Face アクセス トークンに置き換えてください。アクセス トークンは Hugging Face のウェブサイトで取得できます（通常は Settings -> Access Tokens から）。講義スライドに利用方法が記載されていますので、そちらも参照してください。トークンは機密情報ですので、取り扱いには十分注意してください。

```bash
export HF_MODEL_NAME="Qwen/Qwen3-4B"
export HF_USERNAME="[YOUR_HUGGINGFACE_USERNAME]"
export HF_TOKEN="[YOUR_HUGGINGFACE_ACCESS_TOKEN]" 
```

### **3. チューニング用の環境セットアップ**

TPU 上での学習には [MaxText](https://github.com/AI-Hypercomputer/maxtext) を利用します。MaxText は Google が開発しているモデル学習用の OSS ライブラリです。Python / JAX で実装されており、TPU や GPU 上で高速、かつスケーラブルなモデル学習を可能とします。

MaxText を利用した学習環境をセットアップするため、以下の 3 つの手順を実行します。

- GitHub リポジトリの Clone
- Python の仮想環境の作成
- 必要な Python モジュールのインストール

まずは以下のコマンドを実行して MaxTex のリポジトリを Clone し、当該ディレクトリに移動します。

```bash
git clone https://github.com/AI-Hypercomputer/maxtext.git
cd maxtext
```

続いて以下のコマンドを実行して Python の仮想環境の作成し、アクティベーションします。

```bash
export VENV_NAME=maxtext_venv
pip install uv
export PATH="$HOME/.local/bin:$PATH"
uv venv --python 3.12 --seed $VENV_NAME
source $VENV_NAME/bin/activate
```

最後に以下のコマンドを実行して必要なモジュールをインストールします。

```bash
sed -i 's/vllm-tpu/vllm-tpu==0.13.2.post6/g' tools/setup/setup_post_training_requirements.sh
uv pip install -e .[tpu] --resolution=lowest
bash tools/setup/setup_post_training_requirements.sh
```

## **4. モデルのダウンロードと事前準備**

ここまでの手順で環境準備は完了です。続いては Qwen3 4B の事前学習済みモデルの下準備を行います。

MaxText を利用して学習済みのモデルに対してファイン チューニングなどを行う場合、モデルを MaxText が対応する形式で保存する必要があります。今回は Hugging Face からモデルをダウンロードして利用するため、モデルを Hugging Face 形式 (.safetensors) から MaxText が対応する形式に変換します。

以下のコマンドを実行し、MaxText で用意しているモデルの形式変換用のスクリプトを呼び出すことでモデルのダウンロードと形式変換を行います。

```bash
export PRE_TRAINED_MODEL='qwen3-4b'
export BASE_OUTPUT_DIRECTORY=/mnt/disks/checkpoints
export PRE_TRAINED_MODEL_CKPT_DIRECTORY=${BASE_OUTPUT_DIRECTORY}/maxtext/${PRE_TRAINED_MODEL}

python3 -m MaxText.utils.ckpt_conversion.to_maxtext src/MaxText/configs/base.yml \
    model_name=${PRE_TRAINED_MODEL} \
    hf_access_token=${HF_TOKEN} \
    base_output_directory=${PRE_TRAINED_MODEL_CKPT_DIRECTORY} \
    weight_dtype=bfloat16 \
    scan_layers=True \
    skip_jax_distributed_system=True
```

以下のコマンドで `PRE_TRAINED_MODEL_CKPT_DIRECTORY` で指定したディレクトリ内の `0/items` ディレクトリに `_METADATA` と `manifest.ocdbt` のファイル、`d` と `ocdbt.process_0` のディレクトリが含まれることを確認します。

```
ls ${PRE_TRAINED_MODEL_CKPT_DIRECTORY}/0/items
```

## **5. Qwen3 4B モデルのファイン チューニング**

いよいよ Qwen3 4B モデルをファインチューニングしましょう。今回は SFT (Supervised Fine-Tuning) と呼ばれる教師ありファイン チューニングを実施しますが、MaxText では SFT 用のスクリプトも用意されており、MaxText がサポートするモデルであればモデル名や学習後のモデルの出力先などを指定するのみで簡単にファイン チューニングが実施できます。

まずは以下を実行し、モデルの Tokenizer やステップ数、SFT で利用する教師データ、前ステップでダウンロードした SFT の学習元になるモデルの保存先など、学習に必要なデータに関する環境変数を設定します。

```bash
export PRE_TRAINED_MODEL_TOKENIZER='Qwen/Qwen3-4B'
export STEPS=100
export PER_DEVICE_BATCH_SIZE=1
export DATASET_NAME=llm-jp/Synthetic-JP-EN-Coding-Dataset
export TRAIN_SPLIT=train
export TRAIN_DATA_COLUMNS=['messages']
export PRE_TRAINED_MODEL_CKPT_PATH=${PRE_TRAINED_MODEL_CKPT_DIRECTORY}/0/items
```

それぞれの変数の目的は以下のとおりです。

- PRE_TRAINED_MODEL_TOKENIZER: Qwen/Qwen3-4B のトークナイザーの指定
- STEPS: 学習のステップ数
- PER_DEVICE_BATCH_SIZE: バッチサイズ
- DATASET_NAME: Hugging Face Datasets に保存されている教師データ名
- TRAIN_SPLIT: 教師データのバージョン
- TRAIN_DATA_COLUMNS: 学習に使う列名
- PRE_TRAINED_MODEL_CKPT_PATH: 先の手順で保存したモデルの保存先

念のため、以下のコマンドで環境変数が設定されているかを確認します。

```bash
cat << EOF
   PRE_TRAINED_MODEL:           ${PRE_TRAINED_MODEL}
   BASE_OUTPUT_DIRECTORY:       ${BASE_OUTPUT_DIRECTORY}
   PER_DEVICE_BATCH_SIZE:       ${PER_DEVICE_BATCH_SIZE}
   PRE_TRAINED_MODEL_CKPT_PATH: ${PRE_TRAINED_MODEL_CKPT_PATH}
   PRE_TRAINED_MODEL_TOKENIZER: ${PRE_TRAINED_MODEL_TOKENIZER}
   HF_TOKEN:                    ${HF_TOKEN}

EOF
```

すべての環境変数が設定されていたら、以下のコマンドを実行して SFT 学習を実行します。


```bash
python3 -m MaxText.sft.sft_trainer src/MaxText/configs/sft.yml \
    run_name=${PRE_TRAINED_MODEL}-sft \
    base_output_directory=${BASE_OUTPUT_DIRECTORY}/maxtext \
    model_name=${PRE_TRAINED_MODEL} \
    load_parameters_path=${PRE_TRAINED_MODEL_CKPT_PATH} \
    hf_access_token=${HF_TOKEN} \
    tokenizer_path=${PRE_TRAINED_MODEL_TOKENIZER} \
    per_device_batch_size=${PER_DEVICE_BATCH_SIZE} \
    max_target_length=1024 \
    weight_dtype=bfloat16 \
    steps=${STEPS} \
    hf_path=${DATASET_NAME} \
    train_split=${TRAIN_SPLIT} \
    train_data_columns=${TRAIN_DATA_COLUMNS} \
    scan_layers=True \
    profiler=xplane
```

SFT の実行には 5 ~ 10 分程度の時間がかかります。

ファイン チューニングが完了した後、さまざまな環境からもモデルを利用可能とするために Hugging Face にアップロードします。学習用にモデルを MaxText 形式に変換しているため、Hugging Face へモデルをアップロードをする場合は Hugging Face 形式に再変換を行った上でアップロードします。

まずは以下を実行し、モデルを Hugging Face 形式に変換します。

``` bash
python3 -m MaxText.utils.ckpt_conversion.to_huggingface src/MaxText/configs/base.yml \
    model_name=${PRE_TRAINED_MODEL} \
    load_parameters_path=${BASE_OUTPUT_DIRECTORY}/maxtext/${PRE_TRAINED_MODEL}-sft/checkpoints/100/model_params \
    base_output_directory=${BASE_OUTPUT_DIRECTORY}/huggingface/${PRE_TRAINED_MODEL}-sft \
    scan_layers=True \
    weight_dtype=bfloat16 \
    hf_access_token=${HF_TOKEN}
```

続いてモデルをさまざまな環境で利用できるように以下を実行して Hugging Face の自分のレポジトリにアップロードします。このコマンドでは `qwen3-4b-sft-test` という名前でモデルがアップロードされます。

``` bash
hf upload qwen3-4b-sft-test /mnt/disks/checkpoints/huggingface/qwen3-4b-sft --token $HF_TOKEN 
```

## **6. ファイン チューニングしたモデルを利用した推論準備**

ここまでで TPU を利用して Qwen3 4B モデルのファインチューニング (SFT) が完了したので最後にチューニングしたモデルを使った推論を実行してみます。プロダクション環境では GKE や Cloud Run、Vertex AI の利用がおすすめです。後続のラボでは GKE を利用した推論について扱いますがこのラボでは簡単のために CLI を利用した推論を行います。

モデルの推論には推論用のエンジンが必要です。今回は多くの場面で広く利用されている [vLLM](https://docs.vllm.ai/en/latest/) を利用します。vLLM の TPU 対応も進んでおり、GPU で利用する場合と大きな手順の差異はなく簡単に利用できます。

**重要: 推論にはモデルが稼働している vLLM サーバーの他にプロンプトを送るクライアントも必要になります。そのため、以下の手順は Cloud Shell で 2 つのタブを利用します。**

ここまで利用した Shell はサーバー用にそのまま利用し、`CLOUD SHELL ターミナル` と書かれたタブ表示部分の `+` を押下して新しいタブを開きます。(タブにはプロジェクト名が表示されているはずです)

新しく開いたタブで以下のコマンドを実行し、インスタンスに SSH をした上で Python の仮想環境をアクティベーションします。

- VM インスタンスへの SSH 接続
``` bash
export PROJECT_ID=$(gcloud projects list --filter="projectId ~ '^qwiklabs-gcp-' AND projectId != 'qwiklabs-resources'" --format="value(projectId)" | head -n 1)
gcloud compute tpus tpu-vm ssh tpu-v5e-8 --project $PROJECT_ID --zone us-west1-c
```

- SSH 接続後に Python 仮想環境のアクティベーション
```bash
export VENV_NAME=maxtext_venv

cd maxtext
source $VENV_NAME/bin/activate
```

クライアント用の Cloud Shell タブの準備が完了したら今まで利用していたサーバー用の Cloud Shell タブに戻り、以下のコマンドを実行します。

``` bash
vllm serve ${HF_USERNAME}/qwen3-4b-sft-test \
    --download_dir /tmp \
    --disable-log-requests \
    --tensor_parallel_size=1 \
    --max-model-len=8192
```

モデルを TPU 上にロードする必要があるので vLLM が Ready になるまで 5 分程度の時間がかかります。

Ready になりましたら新しく開いたクライアント用の Cloud Shell タブに切り替え、以下のコマンドを実行してチャット用の CLI を実行します。`YOUR_HUGGINGFACE_USERNAME` はご自身のユーザー名に変更ください。

``` bash
export HF_USERNAME="[YOUR_HUGGINGFACE_USERNAME]"

vllm chat --model ${HF_USERNAME}/qwen3-4b-sft-test
```

`>` が表示されて入力待ちになったらチャット画面が Ready なので `Hello` などを送信して挨拶をしてみてください。返答が返ってきたら無事に動作をしています。

## **7. モデルの動作確認**

最後に適切なファイン チューニングができているかを確認します。本来はチューニングに利用したデータセットの特性を鑑みてプロンプトを送信することが望ましいです。しかし、このラボでは計算資源や時間の都合で 100 ステップのみの学習を実行したのでデータセットに含まれるプロンプトに対して同じくデータセット内に含まれる回答が返るかを見てみます。

今回利用した llm-jp/Synthetic-JP-EN-Coding-Dataset のデータセットの中身は Hugging Face の[こちら](https://huggingface.co/datasets/llm-jp/Synthetic-JP-EN-Coding-Dataset/viewer)よりご確認いただけます。

任意のデータを選び、先の手順で起動したチャット画面に `"role": "user"` となっているデータの `content` 部分にかかれている文を入力ください。その返答として、`"role": "assistant"` となっているデータの `content` 内の内容に類似した文章が返ればチューニングは成功しています。

なお、先の手順の `vllm serve` および `vllm chat` を `Qwen/Qwen3-4b` とすることでチューニング前のモデルも試せますので同じプロンプトを送信して結果を比較することもできます。(ただし、今回は 100 ステップのみの学習なので結果に差異が生じない場合もあります)

### **8. クリーンアップ**

以降のラボで GKE 内に TPU ノードを起動するため、Quota 消費などを鑑みて念のため最後にリソースをクリーンアップします。以下のコマンドを実行して TPU VM を削除します。

```bash
gcloud compute tpus tpu-vm delete tpu-v5e-8
```

## **Configurations!**
これで Cloud TPU によるモデルのファイン チューニング (SFT) 編の全てのラボが完了です。TPU を利用したモデルのファイン チューニングとその動作確認を体験いただきました。この経験が、皆さんの今後に役立つことを願っています！