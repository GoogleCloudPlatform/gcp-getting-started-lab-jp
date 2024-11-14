# Movie search demo app

[GIF 動画](https://github.com/GoogleCloudPlatform/gcp-getting-started-lab-jp/blob/master/movie_search_metadata/demo_app/docs/images/movie_search_demo.gif)

![](https://github.com/GoogleCloudPlatform/gcp-getting-started-lab-jp/blob/master/movie_search_metadata/demo_app/docs/images/movie_search_demo.gif)

## 利用手順

新規プロジェクトを作成したら、Owner 権限のユーザーで Cloud Shell を開いて以下のコマンドを実行します。

### コードを取得

```
git clone https://github.com/GoogleCloudPlatform/gcp-getting-started-lab-jp.git
cd gcp-getting-started-lab-jp/movie_search_metadata/demo_app
```

### Vertex AI Search の検索エンジンを構成

```
./vais_setup.sh
```

ドキュメントのインポート処理に 20〜30分程度かかるので、少し気長にお待ちください。

### 検索アプリをデプロイ

```
./deploy.sh
```

デプロイが完了すると、下記のようにアプリの URL が表示されます。

```
Application URL: https://movie-search-app-xxxxxxxxxx-an.a.run.app
```

この URL をブラウザで開くと、次の 2 種類の機能が利用できます。検索対象の動画は、事前に用意された 3 種類の動画のみになります。

- File search：クエリに関連する動画ファイルを検索します。
- Scene search：クエリに関連するシーン（動画ファイル＋タイムスタンプ）を検索します。


**注意**

アプリの URL を知っているユーザーは誰でもアクセス可能な状態になります。

不要な課金を防止するために、デモが終わったらプロジェクトをシャットダウンすることをお勧めします。
