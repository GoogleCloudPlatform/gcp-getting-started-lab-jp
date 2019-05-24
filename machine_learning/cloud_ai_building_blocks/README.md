# Google Cloud AI の AI Building Blocks を試してみよう

GCP (Google Cloud Platform) には Google Cloud AI と呼ばれる 機械学習に関するプロダクト群があります。
この Google Cloud AI は更に Cloud AI Building Blocks と Cloud AI Platform (CAIP) に分かれています。
このページにあるサンプルコードはすべて Cloud AI Building Blocks に関するものです。

## Cloud AI Building Blocks
Cloud AI Building Blocks とは機械学習を専門としないエンジニアでも、簡単に使い始められる Google Cloud AI のプロダクト群です。Cloud AI Building Blocks は更に機械学習 API と Cloud AutoML というプロダクト群に分けられます。**機械学習 API** を使えば、 Google の高性能な機械学習モデルを API 経由で利用できます。一方、 **Cloud AutoML** を使えば、ユーザが用意した学習データを元に高性能なカスタムモデルを簡単に構築・デプロイすることができ、API 経由ですぐに利用し始めることができます。どちらのプロダクトを使った場合でもバックエンドが自動的に伸縮するため、ユーザ側で負荷対策をする必要はありません。次の表は Cloud AI Building Blocks の各プロダクトを、用途別に分類したものです。

|視覚 (sight)                 |言語 (language)              |会話 (conversation)        |構造化データ (unstructured)|
| -------------------------- | --------------------------- | ------------------------ | ----------------------- |
|Cloud Vision API            |Cloud Natural Language API   | Cloud Speech-to-Text API |Cloud AutoML Table       |
|Cloud Video Intelligence API|Cloud Translation API        | Cloud Text-to-Speech API |Recommendations AI       |
|Cloud AutoML Vision         |Cloud AutoML Natural Language|                          |                         |
|Cloud AutoML Video          |Cloud AutoML Translate       |                          |                         |

それぞれのプロダクトに関する説明は GCP のオフィシャルサイトに譲りますが、上記のように Cloud AI Building Blocks はその用途に応じて視覚、言語、会話、そして構造化データに分類されます。このページには [sight_ja.ipynb](https://github.com/Youki/gcp-getting-started-lab-jp/blob/master/machine_learning/cloud_ai_building_blocks/sight_ja.ipynb), [language_ja.ipynb](https://github.com/Youki/gcp-getting-started-lab-jp/blob/master/machine_learning/cloud_ai_building_blocks/language_ja.ipynb), [conversation_ja.ipynb](https://github.com/Youki/gcp-getting-started-lab-jp/blob/master/machine_learning/cloud_ai_building_blocks/conversation_ja.ipynb) という 3 種類のノートブックファイルがありますが、この中ではそれぞれ Cloud Vision API と Cloud Video Intelligence API、 Cloud Natural Language API と Cloud Translation API、Cloud Speech-to-Text API と Cloud Text-to-Speech API のサンプルコードが入っています。残念ながら、多くの人が興味あるところの Cloud AutoML のサンプルコードは Colab 形式で書く予定はいまのところありません。実行完了までに数時間必要になり Colaboratory ならでのインタラクティブ性が失われるためです。

## サンプルコードの実行方法
ipynb ファイルを開き、下記ボタンをクリックしてください。

![Open in Colab](https://colab.research.google.com/assets/colab-badge.svg)

クリックすると Colaboratory が開かれ、サンプルコードを実行できるようになります。
サンプルコードを実行するにあたっては、各種機械学習 API の有効化 (例 Cloud Vision API の [API 有効化手順](https://cloud.google.com/vision/docs/before-you-begin?hl=ja) を参考にしてください) と GCP の API キーが必要になります。API キーを作成する手順については[こちら](https://cloud.google.com/docs/authentication/api-keys?hl=ja#creating_an_api_key)を参照ください。

## サンプルコードを実行する際の注意点
Colaboratory 自体は無料で利用できますが、機械学習 API の利用に関しては課金されるので注意してください。また、sight_ja.ipynb には Cloud Vision API のサンプルコードが入っていますが、その中で利用する画像は別途アップロードする必要があります。もし手元にちょうどいい写真がない場合には、ウェブ上の適切なサイト (例 https://unsplash.com) から写真をダウンロードして試してください。

