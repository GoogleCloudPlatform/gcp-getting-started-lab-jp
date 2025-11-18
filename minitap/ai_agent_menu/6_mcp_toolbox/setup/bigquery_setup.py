#!/usr/bin/env python3
"""
BigQuery セットアップスクリプト
Google Trends パブリックデータセットへのアクセス確認とビューの作成
"""

import os
from google.cloud import bigquery
from google.cloud.exceptions import Conflict, NotFound
import logging

# ログ設定
logging.basicConfig(level=logging.INFO, format='[%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

def setup_bigquery_for_minitap(project_id: str):
    """MiniTAP用のBigQuery環境をセットアップ"""
    
    try:
        # BigQueryクライアントの初期化
        client = bigquery.Client(project=project_id)
        logger.info(f"BigQueryクライアント初期化完了: {project_id}")
        
        # 1. パブリックデータセットアクセステスト
        logger.info("Google Trendsパブリックデータセットのアクセステスト中...")
        
        test_query = """
        SELECT 
            COUNT(*) as total_records,
            COUNT(DISTINCT country_code) as countries,
            MIN(week) as earliest_week,
            MAX(week) as latest_week
        FROM `bigquery-public-data.google_trends.international_top_terms`
        WHERE week >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
        """
        
        query_job = client.query(test_query)
        results = list(query_job.result())
        
        if results:
            result = results[0]
            logger.info("✅ パブリックデータセットアクセス成功!")
            logger.info(f"   📊 直近7日間レコード数: {result.total_records}")
            logger.info(f"   🌍 対象国数: {result.countries}")
            logger.info(f"   📅 データ期間: {result.earliest_week} ～ {result.latest_week}")
        
        # 2. 分析用データセットの作成（オプション）
        dataset_id = f"{project_id}.minitap_analytics"
        
        try:
            dataset = bigquery.Dataset(dataset_id)
            dataset.location = "US"
            dataset.description = "MiniTAP Google Trends分析用データセット"
            
            dataset = client.create_dataset(dataset, exists_ok=True)
            logger.info(f"📁 データセット作成完了: {dataset_id}")
            
        except Conflict:
            logger.info(f"📁 データセット既存: {dataset_id}")
        
        # 3. 便利なビューの作成
        view_id = f"{dataset_id}.recent_global_trends"
        
        view_query = f"""
        CREATE OR REPLACE VIEW `{view_id}` AS
        SELECT
            week,
            country_name,
            country_code,
            term,
            rank,
            refresh_date
        FROM
            `bigquery-public-data.google_trends.international_top_terms`
        WHERE
            week >= DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY)
        ORDER BY
            week DESC, country_code, rank ASC
        """
        
        query_job = client.query(view_query)
        query_job.result()  # 完了まで待機
        
        logger.info(f"👁️ ビュー作成完了: {view_id}")
        
        # 4. サンプルクエリのテスト
        logger.info("サンプル分析クエリのテスト中...")
        
        sample_query = f"""
        SELECT 
            country_name,
            term,
            AVG(rank) as avg_rank,
            COUNT(*) as appearances
        FROM `{view_id}`
        WHERE week >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
        GROUP BY country_name, term
        HAVING appearances >= 2
        ORDER BY country_name, avg_rank
        LIMIT 20
        """
        
        query_job = client.query(sample_query)
        sample_results = list(query_job.result())
        
        logger.info(f"🧪 サンプルクエリ成功: {len(sample_results)}行のデータを取得")
        
        # 5. 設定情報の出力
        config_info = {
            "project_id": project_id,
            "dataset_id": dataset_id,
            "view_id": view_id,
            "public_dataset": "bigquery-public-data.google_trends.international_top_terms",
            "status": "ready"
        }
        
        logger.info("✅ BigQueryセットアップ完了!")
        logger.info("📋 設定情報:")
        for key, value in config_info.items():
            logger.info(f"   {key}: {value}")
        
        return config_info
        
    except Exception as e:
        logger.error(f"❌ BigQueryセットアップエラー: {e}")
        raise

def main():
    """メイン実行関数"""
    project_id = os.environ.get('GOOGLE_CLOUD_PROJECT', 'nooglerproject123')
    
    logger.info("🚀 MiniTAP BigQueryセットアップ開始")
    logger.info(f"📝 プロジェクトID: {project_id}")
    
    try:
        config = setup_bigquery_for_minitap(project_id)
        
        # Jupyter Notebook用の設定コード生成
        setup_code = f'''
# MiniTAP BigQuery 設定
GOOGLE_CLOUD_PROJECT = "{config['project_id']}"
DATASET_ID = "{config['dataset_id']}"
VIEW_ID = "{config['view_id']}"
PUBLIC_DATASET = "{config['public_dataset']}"

# BigQueryクライアント初期化
from google.cloud import bigquery
client = bigquery.Client(project=GOOGLE_CLOUD_PROJECT)

print("✅ BigQuery設定完了")
print(f"📊 プロジェクト: {{GOOGLE_CLOUD_PROJECT}}")
print(f"📁 データセット: {{DATASET_ID}}")
print(f"👁️ ビュー: {{VIEW_ID}}")
'''
        
        # 設定ファイルの出力
        with open("bigquery_config.py", "w", encoding="utf-8") as f:
            f.write(setup_code)
        
        logger.info("📝 設定ファイル生成: bigquery_config.py")
        logger.info("🎉 セットアップ完了! Jupyter Notebookを開始してください。")
        
    except Exception as e:
        logger.error(f"❌ セットアップ失敗: {e}")
        return 1
    
    return 0

if __name__ == "__main__":
    exit(main())
