#!/usr/bin/env python3
"""
Cloud Shell環境でのプロジェクトID自動検出・設定スクリプト
ハンズオン体験用
"""

import os
import subprocess
import sys

def get_current_project_id():
    """現在のプロジェクトIDを自動検出"""
    
    # 方法1: 環境変数から取得
    project_id = os.environ.get('GOOGLE_CLOUD_PROJECT') or os.environ.get('DEVSHELL_PROJECT_ID')
    if project_id:
        print(f"✅ 環境変数からプロジェクトID検出: {project_id}")
        return project_id
    
    # 方法2: gcloudコマンドから取得
    try:
        result = subprocess.run(
            "gcloud config get-value project", 
            shell=True, 
            capture_output=True, 
            text=True, 
            check=True
        )
        project_id = result.stdout.strip()
        if project_id and project_id != "(unset)":
            print(f"✅ gcloud configからプロジェクトID検出: {project_id}")
            return project_id
    except subprocess.CalledProcessError:
        pass
    
    # 方法3: メタデータサーバーから取得（Cloud Shell/GCE環境）
    try:
        result = subprocess.run(
            "curl -s http://metadata.google.internal/computeMetadata/v1/project/project-id -H 'Metadata-Flavor: Google'",
            shell=True,
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            project_id = result.stdout.strip()
            print(f"✅ メタデータサーバーからプロジェクトID検出: {project_id}")
            return project_id
    except:
        pass
    
    return None

def update_tools_yaml(project_id):
    """tools.yamlのプロジェクトIDを更新"""
    tools_yaml_path = "config/tools.yaml"
    
    if not os.path.exists(tools_yaml_path):
        print(f"❌ {tools_yaml_path} が見つかりません")
        return False
    
    # tools.yamlを読み込み
    with open(tools_yaml_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # プロジェクトIDを置換
    import re
    updated_content = re.sub(
        r'project:\s*\S+',
        f'project: {project_id}',
        content
    )
    
    # ファイルに書き込み
    with open(tools_yaml_path, 'w', encoding='utf-8') as f:
        f.write(updated_content)
    
    print(f"✅ tools.yaml のプロジェクトIDを {project_id} に更新しました")
    return True

def update_notebook_config(project_id):
    """Notebook用の.envファイルを作成"""
    env_file_path = "../.env"
    with open(env_file_path, 'w', encoding='utf-8') as f:
        f.write(f"GOOGLE_CLOUD_PROJECT={project_id}\n")
    print(f"✅ {env_file_path} を作成し、Notebook用のプロジェクトIDを設定しました。")

def main():
    print("🔍 Cloud Shell環境でのプロジェクトID自動検出開始...")
    
    # プロジェクトID検出
    project_id = get_current_project_id()
    
    if not project_id:
        print("❌ プロジェクトIDが検出できませんでした")
        print("💡 以下のコマンドでプロジェクトを設定してください:")
        print("   gcloud config set project YOUR_PROJECT_ID")
        return False
    
    print(f"\n📋 検出されたプロジェクトID: {project_id}")
    
    # 設定ファイル更新
    if update_tools_yaml(project_id):
        update_notebook_config(project_id)
        print("\n🎉 プロジェクト設定完了！")
        print("✅ これでハンズオンを開始できます")
        return True
    
    return False

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)