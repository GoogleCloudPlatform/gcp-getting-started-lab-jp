#!/usr/bin/env python3
"""
MCP Toolbox for Databases tools.yaml対応デプロイスクリプト

参考: GenAI Toolbox Deploy to Cloud Run
- Secret Managerにtools.yamlを保存
- Cloud Runにシークレットマウント
- --tools-fileで起動
"""

import subprocess
import os
import sys
import logging
import json
import time
import tempfile
import argparse

# ログ設定
logging.basicConfig(level=logging.INFO, format='[%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

class CustomToolboxDeployer:
    """MCP Toolbox デプロイヤー"""
    
    def __init__(self, project_id, region="us-central1"):
        if not project_id:
            raise ValueError("GCPプロジェクトIDが必要です。")
        self.project_id = project_id
        self.region = region
        self.service_name = "mcp-trends-custom"
        self.sa_name = "mcp-toolbox-sa"
        self.sa_email = f"{self.sa_name}@{project_id}.iam.gserviceaccount.com"
        self.secret_name = "mcp-toolbox-tools-yaml"
        
    def run_command(self, cmd, check=True, capture_output=True):
        """コマンド実行ヘルパー"""
        logger.info(f"実行中: {cmd}")
        try:
            result = subprocess.run(cmd, shell=True, check=check, 
                                  capture_output=capture_output, text=True, timeout=300)
            if result.stdout and capture_output:
                logger.info(result.stdout.strip())
            return result
        except subprocess.CalledProcessError as e:
            logger.error(f"コマンド実行エラー: {e}")
            if e.stderr:
                logger.error(f"エラー詳細: {e.stderr}")
            if check:
                raise
            return e
            
    def setup_gcp_project(self):
        """GCPプロジェクト設定"""
        logger.info("🔧 GCPプロジェクト設定開始")
        
        # プロジェクト設定
        self.run_command(f"gcloud config set project {self.project_id}")
        self.run_command(f"gcloud auth application-default set-quota-project {self.project_id}")
        
        # 必要APIの有効化
        apis = [
            "run.googleapis.com",
            "cloudbuild.googleapis.com",
            "bigquery.googleapis.com",
            "iam.googleapis.com",
            "secretmanager.googleapis.com",
            "aiplatform.googleapis.com",
            "logging.googleapis.com",
            "geminidataanalytics.googleapis.com"
        ]
        
        for api in apis:
            try:
                self.run_command(f"gcloud services enable {api}")
                logger.info(f"✅ {api} 有効化完了")
            except:
                logger.warning(f"⚠️ {api} 有効化スキップ（既に有効化済みの可能性）")
                
        time.sleep(10)  # API有効化完了待機
        
    def setup_service_account(self):
        """サービスアカウントと権限の設定"""
        logger.info("👤 サービスアカウント設定開始")
        
        # サービスアカウント作成（既存の場合はスキップ）
        try:
            self.run_command(f"""
            gcloud iam service-accounts create {self.sa_name} \
              --display-name="MCP Toolbox Service Account" \
              --description="Service account for MCP Toolbox for Databases"
            """.strip())
            logger.info("✅ サービスアカウント作成完了")
        except:
            logger.info("ℹ️ サービスアカウントは既に存在します")
        
        # 必要な権限を付与
        roles = [
            "roles/bigquery.user",
            "roles/cloudaicompanion.user",
            "roles/run.invoker",
            "roles/geminidataanalytics.dataAgentUser",
            "roles/logging.logWriter",
            "roles/storage.objectViewer",
            "roles/secretmanager.secretAccessor"
        ]
        
        for role in roles:
            try:
                self.run_command(f"""
                gcloud projects add-iam-policy-binding {self.project_id} \
                  --member=\"serviceAccount:{self.sa_email}\" \
                  --role=\"{role}\" \
                  --quiet
                """.strip(), capture_output=False)
                logger.info(f"✅ 権限付与完了: {role}")
            except:
                logger.warning(f"⚠️ 権限付与スキップ: {role}")

        # Cloud Buildのための権限設定
        logger.info("🔧 Cloud Buildのための権限設定")
        try:
            project_number = self.run_command(f"gcloud projects describe {self.project_id} --format='value(projectNumber)'").stdout.strip()
            
            service_accounts_to_permission = {
                "Cloud Build SA": f"{project_number}@cloudbuild.gserviceaccount.com",
                "Compute Engine SA": f"{project_number}-compute@developer.gserviceaccount.com"
            }
            
            roles_to_grant = [
                "roles/storage.objectViewer",
                "roles/logging.logWriter",
                "roles/cloudbuild.builds.builder"
            ]

            for sa_name, sa_email in service_accounts_to_permission.items():
                for role in roles_to_grant:
                    try:
                        self.run_command(f"""
                        gcloud projects add-iam-policy-binding {self.project_id} \
                          --member=\"serviceAccount:{sa_email}\" \
                          --role=\"{role}\" \
                          --quiet
                        """.strip(), capture_output=False)
                        logger.info(f"✅ 権限付与完了: {role} for {sa_name}")
                    except:
                        logger.warning(f"⚠️ 権限付与スキップ: {role} for {sa_name}")

        except Exception as e:
            logger.warning(f"⚠️ Cloud Buildの権限設定に失敗しました。手動での確認が必要な場合があります: {e}")
                
    def create_secret_with_tools_yaml(self):
        """Secret Managerにtools.yamlを作成"""
        logger.info("🔐 Secret Managerにtools.yaml保存中")
        
        # 既存シークレット削除
        try:
            self.run_command(f"gcloud secrets delete {self.secret_name} --quiet")
            logger.info("🗑️ 既存シークレット削除")
        except:
            pass
            
        # tools.yamlの内容を読み込み
        tools_yaml_path = os.path.join(os.path.dirname(__file__), '..', 'config', 'tools.yaml')
        if not os.path.exists(tools_yaml_path):
            logger.error(f"設定ファイルが見つかりません: {tools_yaml_path}")
            # Fallback to original path for backwards compatibility
            tools_yaml_path = "tools.yaml"
            if not os.path.exists(tools_yaml_path):
                logger.error(f"設定ファイルが見つかりません: {tools_yaml_path}")
                raise FileNotFoundError("tools.yaml not found in expected locations.")

        with open(tools_yaml_path, "r", encoding="utf-8") as f:
            tools_yaml_content = f.read()
            
        # 一時ファイルにtools.yamlを保存
        with tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".yaml") as temp_file:
            temp_file.write(tools_yaml_content)
            temp_file_path = temp_file.name
            
        try:
            # シークレット作成
            self.run_command(f"gcloud secrets create {self.secret_name} --data-file={temp_file_path}")
            logger.info("✅ Secret Manager にtools.yaml保存完了")
            
            # サービスアカウントにアクセス権付与
            self.run_command(f"""
            gcloud secrets add-iam-policy-binding {self.secret_name} \
              --member="serviceAccount:{self.sa_email}" \
              --role="roles/secretmanager.secretAccessor"
            """.strip())
            logger.info("✅ サービスアカウントにシークレットアクセス権付与完了")
            
        finally:
            # 一時ファイル削除
            os.unlink(temp_file_path)
            
    def create_custom_dockerfile(self):
        """カスタムtools.yaml対応Dockerfileを作成"""
        logger.info("📦 カスタムtools.yaml対応Dockerfile作成中")
        
        dockerfile_content = f"""# MCP Toolbox for Databases - カスタムtools.yaml対応版
# Google Trends BigQuery専用ツール

FROM us-central1-docker.pkg.dev/database-toolbox/toolbox/toolbox:latest

# Cloud Run環境変数
ENV PORT=8080
ENV GOOGLE_CLOUD_PROJECT={self.project_id}

# tools.yamlファイルパス（Secret Managerからマウント）
ENV TOOLS_FILE=/etc/secrets/tools.yaml

# MCP Toolbox カスタム設定起動コマンド
# - カスタムtools.yamlファイル使用
# - Cloud Run用アドレス・ポート設定
CMD ["toolbox", \\
     "--tools-file", "/etc/secrets/tools.yaml", \\
     "--address", "0.0.0.0", \\
     "--port", "8080"]
"""
        
        with open("Dockerfile.custom", "w") as f:
            f.write(dockerfile_content.strip())
            
        # メインDockerfileとしてコピー
        with open("Dockerfile", "w") as f:
            f.write(dockerfile_content.strip())
            
        logger.info("✅ カスタムtools.yaml対応Dockerfile作成完了")
        
    def deploy_to_cloud_run(self):
        """Cloud Runへのカスタムツールデプロイ"""
        logger.info("☁️ Cloud Run カスタムツールデプロイ開始")
        
        # Cloud Runデプロイ（Secret Managerマウント対応）
        deploy_cmd = f"""
        gcloud run deploy {self.service_name} \
          --source . \
          --platform managed \
          --region {self.region} \
          --service-account {self.sa_email} \
          --set-env-vars "GOOGLE_CLOUD_PROJECT={self.project_id},PROJECT_ID={self.project_id}" \
          --set-secrets "/etc/secrets/tools.yaml={self.secret_name}:latest" \
          --allow-unauthenticated \
          --memory 2Gi \
          --cpu 2 \
          --min-instances 1 \
          --max-instances 10 \
          --timeout 300 \
          --port 8080
        """
        
        env = os.environ.copy()
        env['CLOUDSDK_CORE_DISABLE_PROMPTS'] = '1'
        
        result = subprocess.run(
            deploy_cmd.strip().replace('\\\n', ' ').replace('  ', ' '),
            shell=True,
            env=env,
            capture_output=True,
            text=True,
            timeout=600
        )
        
        if result.returncode == 0:
            logger.info("✅ Cloud Run カスタムツールデプロイ成功!")
            logger.info(result.stdout)
            return True
        else:
            logger.error("❌ Cloud Run カスタムツールデプロイ失敗")
            logger.error(result.stderr)
            return False
            
    def get_service_url(self):
        """デプロイされたサービスURLを取得"""
        logger.info("🌐 サービスURL取得中")
        
        try:
            cmd = f'gcloud run services describe {self.service_name} --region {self.region} --format="value(status.url)"'
            result = self.run_command(cmd)
            service_url = result.stdout.strip()
            
            if service_url:
                logger.info(f"✅ サービスURL: {service_url}")
                return service_url
            else:
                logger.error("❌ サービスURL取得失敗")
                return None
                
        except Exception as e:
            logger.error(f"❌ URL取得エラー: {e}")
            return None
            
    def verify_custom_deployment(self, service_url):
        """カスタムツールデプロイ確認"""
        logger.info("🧪 カスタムツールデプロイ確認・テスト開始")
        
        # デプロイ完了待機
        time.sleep(30)
        
        try:
            import requests
            
            # ルートエンドポイントテスト
            response = requests.get(service_url, timeout=30)
            if response.status_code == 200:
                logger.info(f"✅ HTTP接続成功: {response.text}")
            else:
                logger.warning(f"⚠️ HTTP接続異常: {response.status_code}")
                
            return True
            
        except Exception as e:
            logger.warning(f"⚠️ 確認エラー: {e}")
            return False
            
    def update_config_file(self, service_url):
        """設定ファイルの更新"""
        logger.info("📝 設定ファイル更新中")
        
        config = {
            "server_url": service_url,
            "project_id": self.project_id,
            "region": self.region,
            "service_name": self.service_name,
            "service_account": self.sa_email,
            "toolbox_type": "mcp-toolbox-for-databases-custom",
            "configuration": "custom-google-trends-tools",
            "secret_name": self.secret_name,
            "status": "custom_production_ready",
            "deployed_at": time.strftime('%Y-%m-%d %H:%M:%S'),
            "tools": {
                "execute_sql_tool": "BigQueryクエリ実行",
                "bigquery_get_dataset_info": "BigQueryデータセット情報取得",
                "bigquery_get_table_info": "BigQueryテーブル情報取得",
            },
            "toolsets": {
                "google-trends-analysis": "Google Trends分析ツールセット"
            }
        }
        
        config_code = f'''# MCP Toolbox for Databases カスタムtools.yaml本番設定
# Google Trends BigQuery専用ツール
# 自動生成: {time.strftime('%Y-%m-%d %H:%M:%S')}

MCP_CONFIG = {json.dumps(config, indent=4, ensure_ascii=False)}

print("✅ MCP Toolbox for Databases カスタムツール本番環境準備完了")
print(f"🌐 サーバーURL: {{MCP_CONFIG['server_url']}}")
print(f"🏗️ サービス: {{MCP_CONFIG['service_name']}}")
print(f"📊 設定: {{MCP_CONFIG['configuration']}}")
print(f"🔧 カスタムツール数: {{len(MCP_CONFIG['tools'])}}")
'''
        
        # ルートディレクトリにmcp_config.pyを作成
        config_file_path = os.path.join(os.path.dirname(__file__), '..', 'mcp_config.py')
        with open(config_file_path, "w", encoding="utf-8") as f:
            f.write(config_code)
            
        logger.info(f"✅ mcp_config.py 更新完了: {os.path.abspath(config_file_path)}")
        return config
        
    def deploy_complete_custom_system(self):
        """MCPシステムのデプロイ"""
        logger.info("🚀 MCP Toolbox for Databases デプロイ開始")
        
        try:
            # 1. GCPプロジェクト設定
            self.setup_gcp_project()
            
            # 2. サービスアカウント設定
            self.setup_service_account()
            
            # 3. Secret Managerにtools.yaml保存
            self.create_secret_with_tools_yaml()
            
            # 4. カスタムDockerfile作成
            self.create_custom_dockerfile()
            
            # 5. Cloud Runデプロイ
            if not self.deploy_to_cloud_run():
                logger.error("❌ デプロイ失敗")
                return None
                
            # 6. サービスURL取得
            service_url = self.get_service_url()
            if not service_url:
                logger.error("❌ URL取得失敗")
                return None
                
            # 7. デプロイ確認
            verification_success = self.verify_custom_deployment(service_url)
            
            # 8. 設定ファイル更新
            config = self.update_config_file(service_url)
            
            # 9. 報告
            logger.info("🎉 MCP Toolbox for Databases デプロイ完了!")
            logger.info("📋 構成:")
            logger.info(f"   🌐 URL: {service_url}")
            logger.info(f"   🏗️ サービス: {self.service_name}")
            logger.info(f"   👤 サービスアカウント: {self.sa_email}")
            logger.info(f"   🔐 シークレット: {self.secret_name}")
            logger.info(f"   🔧 カスタムツール: {len(config['tools'])}個")
            logger.info(f"   ✅ 動作確認: {'成功' if verification_success else '一部制限あり'}")
            
            return config
            
        except Exception as e:
            logger.error(f"❌ カスタムツールデプロイエラー: {e}")
            return None

def get_gcloud_project_id():
    """gcloud configからプロジェクトIDを取得"""
    try:
        cmd = "gcloud config get-value project"
        result = subprocess.run(cmd, shell=True, check=True, capture_output=True, text=True)
        return result.stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None

def main():
    """メイン実行関数"""
    parser = argparse.ArgumentParser(description="MCP Toolbox for Databases カスタムtools.yaml デプロイスクリプト")
    
    project_id_from_gcloud = get_gcloud_project_id()
    
    parser.add_argument(
        "--project-id",
        help="GCPプロジェクトID。指定しない場合はgcloudの現在の設定が使用されます。",
        default=project_id_from_gcloud
    )
    parser.add_argument(
        "--region",
        default="us-central1",
        help="デプロイ先のリージョン"
    )
    
    args = parser.parse_args()
    
    if not args.project_id:
        logger.error("❌ プロジェクトIDが指定されていません。gcloud config set project <PROJECT_ID> を実行するか、--project-id引数で指定してください。")
        return 1

    logger.info(f"🚀 MCP Toolbox for Databases カスタムtools.yaml デプロイ開始 (Project: {args.project_id}, Region: {args.region})")
    
    try:
        deployer = CustomToolboxDeployer(project_id=args.project_id, region=args.region)
        config = deployer.deploy_complete_custom_system()
    except ValueError as e:
        logger.error(f"❌ 初期化エラー: {e}")
        return 1

    if config:
        logger.info("\n🎯 次のステップ:")
        logger.info("   1. toolbox-coreクライアントでのカスタムツール確認")
        logger.info("   2. Notebookでのカスタムツール実用テスト")
        logger.info("   3. Google Trendsカスタム分析の本格運用開始")
        return 0
    else:
        logger.error("❌ カスタムツールデプロイに失敗しました")
        return 1

if __name__ == "__main__":
    sys.exit(main())
