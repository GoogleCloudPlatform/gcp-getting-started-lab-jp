
# MiniTAP BigQuery 設定
GOOGLE_CLOUD_PROJECT = "able-keep-309711"
DATASET_ID = "able-keep-309711.minitap_analytics"
VIEW_ID = "able-keep-309711.minitap_analytics.recent_global_trends"
PUBLIC_DATASET = "bigquery-public-data.google_trends.international_top_terms"

# BigQueryクライアント初期化
from google.cloud import bigquery
client = bigquery.Client(project=GOOGLE_CLOUD_PROJECT)

print("✅ BigQuery設定完了")
print(f"📊 プロジェクト: {GOOGLE_CLOUD_PROJECT}")
print(f"📁 データセット: {DATASET_ID}")
print(f"👁️ ビュー: {VIEW_ID}")
