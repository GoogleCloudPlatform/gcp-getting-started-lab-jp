# Movie search demo app

## 利用手順

新規プロジェクトを作成したら、Owner 権限のユーザーで Cloud Shell を開いて以下のコマンドを実行します。

### コードを取得

```
git clone https://github.com/GoogleCloudPlatform/gcp-getting-started-lab-jp.git
cd gcp-getting-started-lab-jp/movie_search_metadata/demo_app
```

### Vertex AI Search の検索アプリを構成

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

**注意**

アプリの URL を知っているユーザーは誰でもアクセス可能な状態になります。

不要な課金を防止するために、デモが終わったらプロジェクトをシャットダウンすることをお勧めします。
