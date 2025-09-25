# MCP Toolbox for Databases - カスタムtools.yaml対応版
# Google Trends BigQuery専用ツール

FROM us-central1-docker.pkg.dev/database-toolbox/toolbox/toolbox:latest

# Cloud Run環境変数
ENV PORT=8080
ENV GOOGLE_CLOUD_PROJECT=data-agent-bq

# tools.yamlファイルパス（Secret Managerからマウント）
ENV TOOLS_FILE=/etc/secrets/tools.yaml

# MCP Toolbox カスタム設定起動コマンド
# - カスタムtools.yamlファイル使用
# - Cloud Run用アドレス・ポート設定
CMD ["toolbox", \
     "--tools-file", "/etc/secrets/tools.yaml", \
     "--address", "0.0.0.0", \
     "--port", "8080"]