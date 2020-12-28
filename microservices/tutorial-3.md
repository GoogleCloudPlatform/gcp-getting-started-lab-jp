# ハンズオン：Transactional workflows in microservices architecture

## 1. 事前準備

### 前提ハンズオンの完了

このハンズオンは、[tutorial-1.md](tutorial-1.md) の内容を完了した後に、続けて実施する前提になります。
[tutorial-1.md](tutorial-1.md) を完了したプロジェクト環境を利用して、このハンズオンを続けてください。

### Cloud Shell の起動

これ以降の作業は、基本的には、Cloud Shell 端末でのコマンド操作で行います。

Cloud Shell を開いて、次のコマンドを実行します。ここでは、Project ID を環境変数にセットすると共に、gcloud コマンドのデフォルトプロジェクトに設定します。
（`[your project ID]` の部分はハンズオンを進める環境の Project ID に置き換えてください。）

```
PROJECT_ID=[your project ID]
gcloud config set project $PROJECT_ID
```

「Cloud Shell の承認」というポップアップが表示されますので、「承認」をクリックしてください。

*コマンドの出力例*
```
Updated property [core/project].
```

**注意：作業中に新しい Cloud Shell 端末を開いた場合は、必ず、最初にこのコマンドを実行してください。**
