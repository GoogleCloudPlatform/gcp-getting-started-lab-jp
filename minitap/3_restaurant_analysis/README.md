# Vertex AI Gemini API と連携する Flask アプリケーション

| | |
| --- | --- |
| 日本版更新者 | [Nozomu Yoshida](https://gitlab.com/nozoyoshida)|
| 日本版作成者 | [Kanoko Suzuki](https://moma.corp.google.com/person/kanoko?q=kanoko)|
| US版作成者 | [Alejandro Ballesta](https://gitlab.com/alejandrobr1) |

# Google Gemini による動画分析

この Flask アプリケーションは、Google Cloud Storage にアップロードされた動画を、多言語対応の Google Gemini API を使用して分析します。食事の準備のタイムスタンプを抽出し、在庫、安全性、潜在的な問題に関する洞察、および改善のための提案を提供します。

## 特徴

- **食事準備のタイムスタンプ:** 動画内の各食事の準備の開始時刻と終了時刻を特定し、平均準備時間を計算します。
- **在庫見積もり:** キッチンで見えるさまざまな食材やアイテムの量を概算します。
- **安全性評価:** 動画で観察された肯定的な安全慣行と潜在的な危険の両方を検出して報告します。
- **問題の特定:** 食品調理プロセスにおける運用上の問題やエラーを強調します。
- **ビデオクリップ生成:** 個々の食事準備の短いクリップを作成します。

## アプリケーションのプレビュー

![代替テキスト](static/application_preview_images/index_image.png)
![代替テキスト](static/application_preview_images/inventory_image.png)
![代替テキスト](static/application_preview_images/insight_image.png)

## 要件

- **Python 3.7 以降**
- **Flask**
- **Google Cloud プロジェクト** と以下のもの:
- **Gemini API が有効になっていること**
- **動画アップロード用の Google Cloud Storage バケット**
- **Vertex AI API が有効になっていること**
- **Google Cloud Storage および Vertex AI API へのアクセス権を持つサービスアカウント**
- **以下の Python パッケージ:**
- `google-cloud-storage`
- `vertexai`
- `google-genai`

## アプリケーションをローカルで実行する (Cloud Shell 上で)

Flask アプリケーションをローカルで (Cloud Shell 上で) 実行するには、次の手順を実行する必要があります。

1. Python 仮想環境をセットアップし、依存関係をインストールします。

   Cloud Shell で、次のコマンドを実行します。

   ```bash
   python3 -m venv restaurant-env
   source restaurant-env/bin/activate
   pip install -r requirements.txt
   ```

2. `uploaded_videos` という名前のフォルダを持つ gcp バケットを作成し、テストしたいすべての動画 (.mp4 形式) をアップロードします。

3. アプリケーションを実行する際には、2 つの入力変数にアクセスする必要があります。

   - `project_name` : これは Google Cloud プロジェクト ID です。
   - `bucket_name` : 動画がアップロードされているGCSバケット名です。

   ロケーションはデフォルトで `global` に設定されています。

4. アプリケーションをローカルで実行するには、次のコマンドを実行します。

   Cloud Shell で、次のコマンドを実行します。

   ```bash
   python app.py your-project-id-here your-bucket-name-here
   ```

アプリケーションが起動し、アプリケーションへの URL が提供されます。Cloud Shell の [ウェブプレビュー](https://cloud.google.com/shell/docs/using-web-preview) 機能を使用してプレビューページを起動します。ブラウザでその URL にアクセスしてアプリケーションを表示することもできます。確認したい機能を選択すると、アプリケーションが Vertex AI Gemini API を呼び出し、応答を表示します。

## アプリケーションをビルドして Cloud Run にデプロイする

    Cloud Run へのデプロイはサポートされていません

## コード構造

- `app.py`: メインの Flask アプリケーションファイル。以下のためのルートと関数が含まれています。
- 動画のアップロードと保存の処理。
- 動画分析のための Google Gemini API との連携。
- 結果を表示するための HTML テンプレートのレンダリング。
- `templates/`: ユーザーインターフェイス用の HTML テンプレートが含まれています。
- `static/`: CSS や JavaScript などの静的ファイルが保存されています。

## 設定

- **`bucket_name`:** Google Cloud Storage バケットの名前。
- **`project_name`:** Google Cloud プロジェクトの ID。
- **`main_prompt`:** 準備されているさまざまな食事のタイムスタンプを抽出するために Gemini 用に設計されたプロンプト。
- **`text_prompt`:** 在庫、安全性、問題、提案など、動画の包括的な分析を提供するように Gemini に指示するプロンプト。

## 使用技術

Flask+HTML: アプリケーションと対話するためのユーザーフレンドリーなウェブインターフェイスを作成します。
Cloud Storage: ユーザーからの入力動画を保存します。
Vertex AI Gemini API: 適切なフレームを選択し、画像を編集するための強力な生成 AI 機能を提供します。
使用モデル: Gemini 2.5 Flash

## 注意事項

- 使用するサービスアカウントに、Google Cloud Storage および Gemini API へのアクセスに必要な権限があることを確認してください。
- 分析の精度と詳細は、動画の品質とプロンプトで提供される指示の明確さに大きく依存します。特定のユースケースに合わせて結果を最適化するために、さまざまなプロンプトを試してください。
- このアプリケーションは、Google Gemini API との基本的な統合を示しています。より高度な機能とカスタマイズについては、公式の Google Gemini API ドキュメントを参照してください。
- 完全なデモ表示を取得するには、表示される食事/飲み物の静的画像を、Gemini が各皿を出力するのと同じ名前で、JPEG 拡張子を付けて static フォルダに手動で追加する必要があります。

## ハンズオン演習

app.py の text_prompt の persona 変数の中の「キッチンの観察者」という部分を、「レストランコンサルタント」や「衛生検査官」、「マーケティング担当者」などに変更して、AIの応答がどのように変わるか試してみましょう。
