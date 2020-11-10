# EGG ハンズオン #2-3

## Google Cloud プロジェクトの選択

ハンズオンを行う Google Cloud プロジェクトを作成し、 Google Cloud プロジェクトを選択して **Start/開始** をクリックしてください。

**なるべく新しいプロジェクトを作成してください。**

<walkthrough-project-setup>
</walkthrough-project-setup>

## [解説] ハンズオンの内容

### **内容と目的**

本ハンズオンでは、Cloud Spanner を触ったことない方向けに、インスタンスの作成から始め、Cloud Spanner に接続し API を使ってクエリする簡易アプリのビルドや、 SQL でクエリをする方法などを行います。

本ハンズオンを通じて、 Cloud Spanner を使ったアプリケーション開発における、最初の 1 歩目のイメージを掴んでもらうことが目的です。


### **前提条件**

本ハンズオンははじめて Cloud Spanner を触れれる方を想定しておりますが、Cloud Spanner の基本的なコンセプトや、主キーによって格納データが分散される仕組みなどは、ハンズオン中では説明しません。
事前知識がなくとも本ハンズオンの進行には影響ありませんが、Cloud Spanner の基本コンセプトやデータ構造については、Coursera などの教材を使い学んでいただくことをお勧めします。 


## [解説] 1. ハンズオンで使用するスキーマの説明

今回のハンズオンでは以下のように、3 つのテーブルを利用します。これは、あるゲームの開発において、バックエンド データベースとして Cloud Spanner を使ったことを想定しており、ゲームのプレイヤー情報や、アイテム情報を管理するテーブルに相当するものを表現しています。

![スキーマ](https://storage.googleapis.com/egg-resources/egg3/public/1-1.png "今回利用するスキーマ")

このテーブルの DDL は以下のとおりです、実際にテーブルを CREATE する際に、この DDL は再度掲載します。

```sql
CREATE TABLE players (
player_id STRING(36) NOT NULL,
name STRING(MAX) NOT NULL,
level INT64 NOT NULL,
money INT64 NOT NULL,
) PRIMARY KEY(player_id);
```

```sql
CREATE TABLE items (
item_id INT64 NOT NULL,
name STRING(MAX) NOT NULL,
price INT64 NOT NULL,
) PRIMARY KEY(item_id);
```

```sql
CREATE TABLE player_items (
player_id STRING(36) NOT NULL,
item_id INT64 NOT NULL,
quantity INT64 NOT NULL,
FOREIGN KEY(item_id) REFERENCES items(item_id)
) PRIMARY KEY(player_id, item_id),
INTERLEAVE IN PARENT players ON DELETE CASCADE;
```


## [演習] 2. Cloud Spanner インスタンスの作成

現在 Cloud Shell と Editor の画面が開かれている状態だと思いますが、[Google Cloud のコンソール](https://console.cloud.google.com/) を開いていない場合は、コンソールの画面を開いてください。


### **Cloud Spanner インスタンスの作成**

![](https://storage.googleapis.com/egg-resources/egg3/public/2-1.png)

1. ナビゲーションメニューから「Spanner」を選択

![](https://storage.googleapis.com/egg-resources/egg3/public/2-2.png)

2. 「インスタンスを作成」を選択

### **情報の入力**

![](https://storage.googleapis.com/egg-resources/egg3/public/2-3.png)

以下の内容で設定して「作成」を選択します。
1. インスタンス名：dev-instance
2. インスタンスID：dev-instance
3. 「リージョン」を選択
4. 「asia-northeast1 (Tokyo) 」を選択
5. ノードの割り当て：1
6. 「作成」を選択

### **インスタンスの作成完了**
以下の画面に遷移し、作成完了です。
どのような情報が見られるか確認してみましょう。

![](https://storage.googleapis.com/egg-resources/egg3/public/2-4.png)

### **スケールアウトとスケールインについて**

Cloud Spanner インスタンスノード数を変更したい場合、編集画面を開いてノードの割り当て数を変更することで、かんたんに行われます
ノード追加であってもノード削減であっても、一切のダウンタイムなく実施することができます。

なお補足ですが、たとえ 1 ノード構成であっても裏は多重化されており、単一障害点がありません。ノード数は可用性の観点ではなく、純粋に性能の観点でのみ増減させることができます。

![](https://storage.googleapis.com/egg-resources/egg3/public/2-5.png)

## [演習] 3. 接続用テスト環境作成 Cloud Shell 上で構築

作成した Cloud Spanner に対して各種コマンドを実行するために Cloud Shell を準備します。

今回はハンズオンの冒頭で起動した Cloud Shell が開かれていると思います。今回のハンズオンで使うパスと、プロジェクト ID が正しく表示されていることを確認してください。以下のように、青文字のパスに続いて、かっこにくくられてプロジェクト ID が黄色文字で表示されています。このプロジェクト ID は各個人の環境でお使いのものに読み替えてください。

![](https://storage.googleapis.com/egg-resources/egg3/public/3-2.png)

もしプロジェクトIDが表示されていない場合、以下の図の様に、青字のパスのみが表示されている状態だと思います。以下のコマンドを Cloud Shell で実行し、プロジェクトIDを設定してください。

![](https://storage.googleapis.com/egg-resources/egg3/public/3-3.png)

```bash
gcloud config set project <今回使う Google Cloud のプロジェクト ID>
``` 


続いて、環境変数 `PROJECT_ID` に、各自で利用しているプロジェクトのIDを格納しておきます。以下のコマンドを、Cloud Shell のターミナルで実行してください。

```bash
export PROJECT_ID=$(gcloud config list project --format "value(core.project)")
```

以下のコマンドで、正しく格納されているか確認してください。
echo の結果が空の場合、1つ前の手順で gcloud コマンドでプロジェクトIDを取得できていません。gcloud config set project コマンドで現在お使いのプロジェクトを正しく設定してください。

```bash
echo $PROJECT_ID
```

また以下のコマンドで、現在いるディレクトリを確認してください。

```bash
pwd
```

以下のようなパスが表示されると思います。

```
/home/<あなたのユーザー名>/cloudshell_open/gcp-getting-started-lab-jp/gaming/egg2-3
```

過去に他の E.G.G のハンズオンを同一環境で実施している場合、***gcp-getting-started-lab-jp-0*** や ***gcp-getting-started-lab-jp-1*** のように末尾に数字がついたディレクトリを、今回の egg2-3 用のディレクトリとしている場合があります。誤って過去のハンズオンで使ったディレクトリを使ってしまわぬよう、**今いる今回利用してるディレクトリを覚えておいてください。**


## [解説] 4. Cloud Spanner 接続クライアントの準備

Cloud Spanner へのデータの読み書きには、様々な方法があります。

### **クライアント ライブラリ を使用しアプリケーションを作成し読み書きする** 

クライアント ライブラリ を使用しアプリケーションを作成し読み書きする方法が代表的なものであり、ゲームサーバー側のアプリケーション内では、`C++`, `C#`, `Go`, `Java`, `Node.js`, `PHP`, `Python`, `Ruby` といった各種言語用のクライアント ライブラリを用いて、Cloud Spanner をデータベースとして利用します。クライアント ライブラリ内では以下の方法で、Cloud Spanner のデータを読み書きすることができます。
- アプリケーションのコード内で API を用いて読み書きする
- アプリケーションのコード内で SQL を用いて読み書きする

またトランザクションも実行することが可能で、リードライト トランザクションはシリアライザブルの分離レベルで実行でき、強い整合性を持っています。またリードオンリー トランザクションを実行することも可能で、トランザクション間の競合を減らし、ロックやそれに伴うトランザクションの abort を減らすことができます。

### **Cloud Console の GUI または gcloud コマンドを利用する** 

Cloud Console の GUI または gcloud コマンドを利用する方法もあります。こちらはデータベース管理者が、直接 SQL を実行したり、特定のデータを直接書き換える場合などに便利です。
 
### **その他 Cloud Spanner 対応ツールを利用する**

これは Cloud Spanner が直接提供するツールではありませんが、 `spanner-cli` と呼ばれる、対話的に SQL を発行できるツールがあります。これは Cloud Spanner Ecosystem と呼ばれる、Cloud Spanner のユーザーコミュニティによって開発メンテナスが行われているツールです。MySQL の mysql コマンドや、PostgreSQL の psql コマンドの様に使うことのできる、非常に便利なツールです。

本ハンズオンでは、主に上記の方法で読み書きを試します。

## [演習] 4. Cloud Spanner 接続クライアントの準備 

### **Cloud Spanner に書き込みをするアプリケーションのビルド**

まずはクライアント ライブラリを利用したアプリケーションを作成してみましょう。

Cloud Shell では、今回利用する `egg2-3` のディレクトリにいると思います。
spanner というディレクトリがありますので、そちらに移動します。

```bash
cd spanner
```

ディレクトリの中身を確認してみましょう。

```bash
ls -la
```

`addplayer.go` という名前のファイルが見つかります。
これは Cloud Shell の Editor でも確認することができます。

`egg2-3/spanner/addplayer.go` を Editor から開いて中身を確認してみましょう。

```bash
cloudshell edit addplayer.go
```

![](https://storage.googleapis.com/egg-resources/egg3/public/4-1.png)

このアプリケーションは、今回作成しているゲームで、新規ユーザーを登録するためのアプリケーションです。
実行すると自動的にユーザー ID が採番され、Cloud Spanner の players テーブルに、新規ユーザー情報をデフォルト値で書き込みます。

以下のコードが実際にその処理を行っている部分です。

```go
func addNewPlayer(ctx context.Context, client *spanner.Client) error {
	tblColumns := []string{"player_id", "name", "level", "money"} // Players Table Schema
	randomid, _ := uuid.NewRandom() // Get a new Primary Key

	// Insert a recode using mutation API
	m := []*spanner.Mutation{
		spanner.InsertOrUpdate("players", tblColumns, []interface{}{randomid.String(), "player-" + randomid.String(), 1, 100}),
	}

	_, err := client.Apply(ctx, m)
	if err != nil {
		log.Fatal(err)
		return err
	}
	log.Printf(">> A new Player with the ID %v has been added!\n", randomid.String())
	return nil
}
```


次にこの Go 言語で書かれたソースコードをビルドしてみましょう。

次のコマンドを実行し、ビルドの準備をします。これにより、必要な依存ライブラリが自動的にダウンロードされます。

```bash
go mod init addplayer
```

そして、次のコマンドでビルドをします。初回ビルド時は、依存ライブラリのダウンロードが行われるため、少し時間がかかります。
1分程度でダウンロード及びビルドが完了します。

```bash
go build addplayer.go
```

ビルドされたバイナリがあるか確認してみましょう。
`addplayer` というバイナリが作られているはずです。これで Cloud Spanner に接続して、書き込みを行うアプリケーションができました。

```bash
ls -la
```

### **spanner-cli のインストール**

ゲームのデータを読み書きするには、専用のアプリケーションを作ったほうが良いです。しかし、時には SQL で Cloud Spanner 上のデータベースを直接読み書きすることも必要でしょう。そんなときに役に立つのが、対話的に SQL をトランザクションとして実行することができる、 **spanner-cli** です。

Google Cloud が提供しているわけではなく、Cloud Spanner Ecosystem と呼ばれるコミュニティによって開発進められており、GitHub 上で公開されています。

Cloud Shell のターミナルに、以下のコマンド入力し、spanner-cli の Linux 用のバイナリをインストールします。

```bash
go get -u github.com/cloudspannerecosystem/spanner-cli
```

## [演習] 5. テーブルの作成

### **データベースの作成**

まだ Cloud Spanner のインスタンスしか作成していないので、データベース及びテーブルを作成していきます。

1つの Cloud Spanner インスタンスには、複数のデータベースを作成することができます。

![](https://storage.googleapis.com/egg-resources/egg3/public/5-1.png)

![](https://storage.googleapis.com/egg-resources/egg3/public/5-2.png)

1. dev-instnace を選択すると画面が遷移します
2. データベースを作成を選択します

### **データベース名の入力**

![](https://storage.googleapis.com/egg-resources/egg3/public/5-3.png)
名前に「player-db」を入力して「次へ」を選択します。


### **データベーススキーマの定義**

![](https://storage.googleapis.com/egg-resources/egg3/public/5-4.png)
スキーマを定義する画面に遷移します。

1. テキストとして編集のトグルボタンを選択すると、DDL を直接入力できるようになります。

2. のエリアに、以下の DDL を直接貼り付けます。

```sql
CREATE TABLE players (
player_id STRING(36) NOT NULL,
name STRING(MAX) NOT NULL,
level INT64 NOT NULL,
money INT64 NOT NULL,
) PRIMARY KEY(player_id);

CREATE TABLE items (
item_id INT64 NOT NULL,
name STRING(MAX) NOT NULL,
price INT64 NOT NULL,
) PRIMARY KEY(item_id);

CREATE TABLE player_items (
player_id STRING(36) NOT NULL,
item_id INT64 NOT NULL,
quantity INT64 NOT NULL,
FOREIGN KEY(item_id) REFERENCES items(item_id)
) PRIMARY KEY(player_id, item_id),
INTERLEAVE IN PARENT players ON DELETE CASCADE;
```

3. の作成を選択すると、テーブル作成が開始します。

### **データベースの作成完了**

![](https://storage.googleapis.com/egg-resources/egg3/public/5-5.png)

うまくいくと、データベースが作成されると同時に 3 つのテーブルが生成されています。

## [演習] 6. データの書き込み：アプリケーション

### **アプリケーションから player データの追加**

先程ビルドした `addplayer` コマンドを、以下の引数で実行します。

```bash
./addplayer projects/${PROJECT_ID}/instances/dev-instance/databases/player-db
```

以下の様なログが出力されれば完了で、生成された IDを控えておきましょう。

ID例：f016b937-c777-4806-86ec-1c7023d1bc55（左のIDは例であり、IDは毎回変わります）

この ID はアプリケーションによって自動生成されたユーザー ID で、データベースの観点では、player テーブルの主キーになります。

### **メモ💡Cloud Spanner の主キーのひみつ**

UUIDv4 を使ってランダムな ID を生成していますが、これは主キーを分散させるためにこのような仕組みを使っています。一般的な RDBMS では、主キーはわかりやすさのために連番を使うことが多いですが、Cloud Spanner は主キー自体をシャードキーのように使っており、主キーに連番を使ってしまうと、新しく生成された行が常に一番うしろのシャードに割り当てられてしまうからです。

addplayer.go 中の以下のコードで UUID を生成し、主キーとして利用しています。
randomid, _ := uuid.NewRandom()

ちなみに Cloud Spanner では、このシャードのことを「スプリット」と呼んでいて、スプリットは必要に応じて自動的に分割されていきます。


## [演習] 6. データの書き込み： Cloud Console の GUI

### **GUI コンソールから player データ確認**

![](https://storage.googleapis.com/egg-resources/egg3/public/6-1.png)

1. 対象テーブル「players」を選択
2. 「データ」タブを選択
3. Cloud Console 上の「データ」タブから追加したレコードを確認することができます。

ここからも今回生成された ID がわかります。


### **GUI コンソールから player_items データ追加**

![](https://storage.googleapis.com/egg-resources/egg3/public/6-2.png)

続いて、データを書き込んでみます。この例では、生成されたプレイヤーに、アイテムを追加する想定です。

1. 対象テーブル「player_items」を選択
2. 「データ」タブを選択
3. 「挿入」を選択



### **外部キー制約による挿入失敗の確認**

![](https://storage.googleapis.com/egg-resources/egg3/public/6-3.png)

テーブルのカラムに合わせて値を入力します。

- player_id：「データの書き込み - クラアントライブラリ」で控えた ID
 (例：f016b937-c777-4806-86ec-1c7023d1bc55)
- item_id：1
- quantity：1

入力したら「保存」を選択します。
以下のようなエラーが出るはずです。

![](https://storage.googleapis.com/egg-resources/egg3/public/6-4.png)


### **GUI コンソールから items データ追加**

![](https://storage.googleapis.com/egg-resources/egg3/public/6-5.png)

item データを書き込んでみます。この例では、ゲーム全体として新たなアイテムを追加する想定です。

1. 対象テーブル「items」を選択
2. 「データ」タブを選択
3. 「挿入」を選択


### **GUI コンソールから items データ追加**

![](https://storage.googleapis.com/egg-resources/egg3/public/6-6.png)

テーブルのカラムに合わせて値を入力します。

- item_id：1
- name：薬草
- price：50

入力したら「保存」を選択します。


### **GUI コンソールから player_items データ追加**

![](https://storage.googleapis.com/egg-resources/egg3/public/6-7.png)

テーブルのカラムに合わせて値を入力します
。
- player_id：「データの書き込み - クラアントライブラリ」で控えた ID
 (例：f016b937-c777-4806-86ec-1c7023d1bc55)
- item_id：1
- quantity：1

入力したら「保存」を選択します。
今度は成功するはずです。



### **GUI コンソールから player データの修正**

![](https://storage.googleapis.com/egg-resources/egg3/public/6-8.png)

1. 対象テーブル「players」を選択
2. 「データ」タブを選択
3. 追加されているユーザーのチェックボックスを選択
4. 編集ボタンを選択
 
### **GUI コンソールから player データの修正**

![](https://storage.googleapis.com/egg-resources/egg3/public/6-9.png)

テーブルのカラムに合わせて値を入力します。

- name：テスター01

入力したら「保存」を選択します。
このようにデータの修正も簡単に行なえます

## [演習] 6. データの書き込み： Cloud Console から SQL

### **SQL による items 及び player_items**

![](https://storage.googleapis.com/egg-resources/egg3/public/6-10.png)

1. 「クエリ」を選択
2. 次ページの SQL を入力欄に貼り付け
3. 「クエリを実行」を選択

この様にすると、任意の SQL を実行できます。

### **SQL による items 及び player_items の挿入**

以下の SQL を「DDLステートメント」そのまま貼り付け、「クエリを実行」を選択してください。

```sql
INSERT INTO items (item_id, name, price)
VALUES (2, 'すごい薬草', 500);
```

書き込みに成功すると、
結果表に「1 行が挿入されました」と表示されます

同様に、以下の SQL を「DDLステートメント」そのまま貼り付け、「クエリを実行」を選択してください。

```sql
INSERT INTO player_items (player_id, item_id, quantity)
VALUES ('f016b937-c777-4806-86ec-1c7023d1bc55', 2, 5);
```

書き込みに成功すると、
結果表に「1 行が挿入されました」と表示されます

## [演習] 6. データの書き込み： spanenr-cli から SQL

### **SQL によるインタラクティブな操作**

以下の通りコマンドを実行すると、Cloud Spanner に接続できます。

```bash
spanner-cli -p $PROJECT_ID -i dev-instance -d player-db
```

![](https://storage.googleapis.com/egg-resources/egg3/public/6-11.png)

例えば、以下のような SELECT 文を実行し、プレイヤーが所持しているアイテム一覧を表示してみましょう。

```sql
SELECT players.name, items.name, player_items.quantity FROM players
JOIN player_items ON players.player_id = player_items.player_id
JOIN items ON player_items.item_id = items.item_id;
```

先程の SELECT 文の頭に EXPLAIN を追加して実行してみましょう。クエリプラン（実行計画）を表示することができます。クエリプランは Cloud Console 上でも表示できます。


```sql
EXPLAIN
SELECT players.name, items.name, player_items.quantity FROM players
JOIN player_items ON players.player_id = player_items.player_id
JOIN items ON player_items.item_id = items.item_id;
```

### **spanner-cli の使い方**

[spanner-cli の GitHubリポジトリ](https://github.com/cloudspannerecosystem/spanner-cli) には、spanner-cli の使い方が詳しく乗っています。これを見ながら、Cloud Spanner に様々なクエリを実行してみましょう。

## **Thank You!**

以上で、今回の Cloud Spanner ハンズオンは完了です。あとはデータベースとして Cloud Spanner を使っていくだけです！