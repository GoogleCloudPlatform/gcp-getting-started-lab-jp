import io
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

from google import genai
from google.genai import types
from flask import Flask, render_template, request, jsonify, Response
from flask_cors import CORS
from google.cloud import storage

# model
MODEL_NAME = 'gemini-2.5-flash'

# main_prompt用スキーマ
meal_preparation_schema = {
    "type": "ARRAY",
    "items": {
        "type": "OBJECT",
        "properties": {
            "meal": {"type": "STRING", "description": "食事の具体的な名前（例：「ケバブサンド」）。必ず日本語で記述。"},
            "start": {"type": "STRING", "description": "準備開始時刻のタイムスタンプ (MM:SS)。"},
            "end": {"type": "STRING", "description": "顧客への提供完了時刻のタイムスタンプ (MM:SS)。"},
            "qty": {"type": "NUMBER", "description": "このトランザクションで準備された食事の数量。"},
            "tool": {"type": "STRING", "description": "この食事の準備に使用された主要な調理器具（例：「フライヤー」、「グリル」）。"},
            "ingredient": {"type": "ARRAY", "items": {"type": "STRING"}, "description": "この食事に使用された主な材料のリスト。"}
        },
        "required": ["meal", "start", "end", "qty", "tool", "ingredient"]
    }
}

# text_prompt用スキーマ
analysis_report_schema = {
    "type": "OBJECT",
    "properties": {
        "inventory": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "name": {"type": "STRING"},
                    "qty": {"type": "NUMBER"}
                },
                "required": ["name", "qty"]
            }
        },
        "safety": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "moment": {"type": "STRING"},
                    "type": {"type": "STRING", "enum": ["positive", "negative"]}
                },
                "required": ["moment", "type"]
            }
        },
        "issue": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "issue": {"type": "STRING"}
                },
                "required": ["issue"]
            }
        },
        "suggestions": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "suggestion": {"type": "STRING"}
                },
                "required": ["suggestion"]
            }
        }
    },
    "required": ["inventory", "safety", "issue", "suggestions"]
}


# Google Cloudプロジェクトとバケット情報を環境変数から初期化
GOOGLE_CLOUD_PROJECT = os.getenv('PROJECT_ID')
BUCKET_NAME = os.getenv('BUCKET_NAME')
GOOGLE_CLOUD_LOCATION = ('asia-northeast1')

# 必須の環境変数が設定されているかチェック
if not GOOGLE_CLOUD_PROJECT or not BUCKET_NAME:
    raise ValueError("必須の環境変数 GOOGLE_CLOUD_PROJECT と BUCKET_NAME が設定されていません。")

# bucket_name 変数も更新
bucket_name = BUCKET_NAME

# ビデオから料理準備データを抽出するためのメインプロンプト（日本語化）
main_prompt = """
あなたはフードカウンターの観察者です。従業員が食事の準備を始めてから顧客に渡すまでの時間を追跡します。
顧客がいる間の食事トランザクションのみを記録してください。
スキーマに基づき、ビデオ内で確認できた全ての食事トランザクションのリストを時系列で出力してください。
- meal (食事名): 見える材料から具体的な日本語名を付けてください（例：「チキンラップ」、「フィッシュアンドチップス」）。
- start (開始時刻): 顧客のための準備を開始したタイムスタンプ (MM:SS)。
- end (終了時刻): 準備が完了し、顧客に手渡されたタイムスタンプ (MM:SS)。
- qty (数量): このトランザクションでの数量。
- tool (調理器具): この食事の準備に使用された主要な調理器具（例：「フライヤー」、「グリル」）。
- ingredient (材料): この食事に使用された主な材料のリスト。
"""

# ビデオコンテンツを分析し、洞察を提供するためのプロンプト（日本語化・日本語出力指定）
persona = "キッチンの観察者" # ← ハンズオン演習箇所
text_prompt = f"""
あなたはプロの{persona}です。このビデオを分析し、詳細なレポートを日本語で作成してください。
スキーマに基づき、以下の情報を提供してください。
- inventory (在庫): キッチンにある機器や備品の在庫数を悲観的に見積もってください。
- safety (安全性): 安全面での良い点(positive)と悪い点(negative)を挙げてください。
- issues (問題点): 調理プロセスにおける問題点やエラーをリストアップしてください。
- suggestions (提案): ビジネス改善のための具体的な提案をしてください。
"""

# Client を初期化
try:
    client = genai.Client(
        vertexai=True, 
        project=GOOGLE_CLOUD_PROJECT, 
        location=GOOGLE_CLOUD_LOCATION
    )
except Exception as e:
    print(f"Failed to initialize Gemini Client. Ensure authentication is set up. Error: {e}")
    client = None

# グローバル変数
current_video = ""

# Flaskアプリを初期化
app = Flask(__name__, static_folder='static', static_url_path='/static')
CORS(app)


def _extract_json(text: str) -> str:
    text = text.strip()
    match = re.search(r"```json\s*([\s\S]*?)\s*```", text)
    if match:
        return match.group(1).strip()
    match = re.search(r"```\s*([\s\S]*?)\s*```", text)
    if match:
        return match.group(1).strip()
    return text


def call_gemini(prompt: str, video_link: str, response_schema: Optional[Dict] = None) -> str:
    """
    辞書ベースのスキーマを使用してGeminiモデルを呼び出します。
    """
    if client is None:
        raise RuntimeError("Gemini client is not initialized.")
        
    video_part = types.Part.from_uri(mime_type="video/mp4", file_uri=video_link)

    config_dict = {
        "temperature": 0,
        "max_output_tokens": 8192,
        "safety_settings": [
            types.SafetySetting(category=types.HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT, threshold=types.HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE),
            types.SafetySetting(category=types.HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT, threshold=types.HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE),
            types.SafetySetting(category=types.HarmCategory.HARM_CATEGORY_HARASSMENT, threshold=types.HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE)
        ]
    }

    if response_schema:
        config_dict["response_mime_type"] = "application/json"
        config_dict["response_schema"] = response_schema
    else:
        config_dict["response_mime_type"] = "text/plain"

    config = types.GenerateContentConfig(**config_dict)

    response = client.models.generate_content(
        model=MODEL_NAME,
        contents=[prompt, "video: ", video_part],
        config=config)
        
    print("--- Gemini API Response ---")
    print(response.text)
    print("-------------------------")
    return response.text


@app.after_request
def after_request(response):
    response.headers.add('Access-Control-Allow-Origin', '*')
    response.headers.add('Access-Control-Allow-Headers', 'Content-Type,Authorization')
    response.headers.add('Access-Control-Allow-Methods', 'GET,PUT,POST,DELETE,OPTIONS')
    return response


@app.route('/get_video_blob', methods=['POST'])
def get_video_blob():
    try:
        global current_video
        data = request.get_json()
        current_video = data.get('gsUrl')
        gs_url = current_video
        
        if not gs_url or not gs_url.startswith('gs://'):
            return jsonify({'error': 'Invalid or missing GS URL'}), 400
            
        bucket_name_from_url, object_name = gs_url[5:].split('/', 1)
        storage_client = storage.Client(project=GOOGLE_CLOUD_PROJECT)
        bucket = storage_client.bucket(bucket_name_from_url)
        blob = bucket.blob(object_name)
        video_data = io.BytesIO()
        blob.download_to_file(video_data, raw_download=True)
        video_data.seek(0)
        return Response(video_data, mimetype='video/mp4', headers={'Content-Disposition': f'attachment; filename={object_name}'})
    except Exception as e:
        print(f"Error in get_video_blob: {e}")
        return jsonify({'error': str(e)}), 500


def list_mp4_files(bucket_name: str) -> list[str]:
    try:
        storage_client = storage.Client(project=GOOGLE_CLOUD_PROJECT)
        bucket = storage_client.bucket(bucket_name)
        blobs = bucket.list_blobs()
        return [blob.name for blob in blobs if blob.name.endswith('.mp4')]
    except Exception as e:
        print(f"Error listing files in bucket {bucket_name}: {e}")
        return []


@app.route('/')
def index():
    video_files = list_mp4_files(bucket_name)
    return render_template('index.html', video_files=video_files, text_prompt=text_prompt, bucket_name=bucket_name)


@app.route('/sample.html')
def sample():
    return render_template('sample.html')


@app.route('/generate_timestamps')
def generate_timestamps_route_get():
    video_url = current_video
    if not video_url:
        return "No video selected", 400

    try:
        # タイムスタンプ抽出
        timestamps_json_str = call_gemini(main_prompt, video_link=video_url, response_schema=meal_preparation_schema)
        pretty_timestamps_json_str = json.dumps(json.loads(timestamps_json_str), indent=4, ensure_ascii=False)
        meal_times = parse_meal_data(timestamps_json_str, video_url)

        # 詳細分析
        analysis_json_str = call_gemini(text_prompt, video_link=video_url, response_schema=analysis_report_schema)
        analysis_data = json.loads(analysis_json_str)
        pretty_analysis_json_str = json.dumps(analysis_data, indent=4, ensure_ascii=False)

        if not isinstance(analysis_data, dict) or 'inventory' not in analysis_data:
             raise ValueError(f"Invalid structure in API response for analysis. Received: {analysis_json_str})")
             
        inventory_labels = [item.get('name', 'N/A') for item in analysis_data.get('inventory', [])]
        inventory_values = [item.get('qty', 0) for item in analysis_data.get('inventory', [])]

        positive_moments = [m.get('moment', '') for m in analysis_data.get('safety', []) if m.get('type') == 'positive']
        negative_moments = [m.get('moment', '') for m in analysis_data.get('safety', []) if m.get('type') == 'negative']
        
        # スキーマで issue -> issues に変更したため .get('issue', [])
        issues_list = analysis_data.get('issue', [])
        suggestions_list = analysis_data.get('suggestions', [])

        return render_template('results_page.html',
                            data=meal_times,
                            meal_times=meal_times,
                            prompt="<<video>>\n" + main_prompt,
                            textPrompt=text_prompt,
                            jsonData=pretty_timestamps_json_str,
                            dataJsonData=analysis_json_str,
                            inventory_labels=inventory_labels,
                            inventory_values=inventory_values,
                            positive_moments=positive_moments,
                            negative_moments=negative_moments,
                            issues=issues_list,
                            suggestions=suggestions_list,
                            api_data=analysis_data,
                            gemini_response=pretty_analysis_json_str,
                            )
    except Exception as e:
        error_message = f"Error during analysis generation: {type(e).__name__}: {e}"
        print(error_message)
        import traceback
        traceback.print_exc()
        return f"An error occurred during analysis: {e}", 500

def delete_mp4_files(folder_path: str):
    folder_path = Path(folder_path)
    if not folder_path.is_dir():
        return
    for file_path in folder_path.iterdir():
        if file_path.is_file() and file_path.suffix.lower() == '.mp4':
            try:
                os.remove(file_path)
            except Exception as e:
                print(f"Error deleting {file_path}: {e}")

def parse_meal_data(json_string: str, video_url: str) -> Dict[str, Dict[str, Any]]:
    try:
        data = json.loads(_extract_json(json_string))
    except json.JSONDecodeError as e:
        print(f"Error decoding JSON string: {e}\nString: {json_string}")
        return {}

    meal_times = {}
    videos = {}
    delete_mp4_files("./static")
    os.makedirs("./static", exist_ok=True)

    if not isinstance(data, list):
        print(f"Warning: Expected a list of meals, but got: {type(data)}")
        return {}

    for item in data:
        meal = item.get("meal")
        start = item.get("start")
        end = item.get("end")
        qty = item.get("qty")
        tool = item.get("tool")
        ingredient = item.get("ingredient")

        if not all([meal, start, end, qty is not None, tool, ingredient]):
            print(f"Warning: Skipping item due to missing data: {item}")
            continue

        try:
            start_parts = start.split(":")
            end_parts = end.split(":")
            if len(start_parts) != 2 or len(end_parts) != 2:
                raise ValueError("Invalid time format (expected MM:SS)")
            start_minutes, start_secs = int(start_parts[0]), int(start_parts[1])
            end_minutes, end_secs = int(end_parts[0]), int(end_parts[1])
        except (ValueError, TypeError) as e:
            print(f"Warning: Invalid time format for meal '{meal}': {e}. Skipping.")
            continue

        start_seconds = start_minutes * 60 + start_secs
        end_seconds = end_minutes * 60 + end_secs
        duration = end_seconds - start_seconds

        if duration < 0:
            print(f"Warning: Negative duration for meal '{meal}'. Skipping.")
            continue

        if meal not in meal_times:
            meal_times[meal] = {"total_time": 0, "total_qty": 0, "transaction_count": 0, "tools": set(), "ingredients": set()}
        meal_times[meal]["total_time"] += duration
        meal_times[meal]["total_qty"] += qty
        meal_times[meal]["transaction_count"] += 1
        meal_times[meal]["tools"].add(tool)
        if isinstance(ingredient, list):
            meal_times[meal]["ingredients"].update(ingredient)
        else:
            meal_times[meal]["ingredients"].add(ingredient)

    for meal in meal_times:
        if meal_times[meal]["transaction_count"] > 0:
            meal_times[meal]["avg_time"] = round(meal_times[meal]["total_time"] / meal_times[meal]["transaction_count"], 2)
        else:
            meal_times[meal]["avg_time"] = 0

        meal_times[meal]["tools"] = list(meal_times[meal]["tools"])
        meal_times[meal]["ingredients"] = list(meal_times[meal]["ingredients"])

        clip_item = next((item for item in data if item.get('meal') == meal), None)
        if clip_item and meal not in videos:
            safe_filename = re.sub(r'[\\/*?:"<>| ]', '_', meal)
            output_filename = f"static/{safe_filename}.mp4"
            try:
                create_video_clip(clip_item['start'], clip_item['end'], output_filename, video_url)
                videos[meal] = 1
            except Exception as e:
                print(f"Failed to create video clip for {meal}: {e}")

    return meal_times


def create_video_clip(start: str, end: str, output_file: str, input_video_url: str):
    if not input_video_url or not input_video_url.startswith('gs://'):
        print(f"Skipping video clip creation due to invalid input URL: {input_video_url}")
        return
    try:
        storage_client = storage.Client(project=GOOGLE_CLOUD_PROJECT)
        bucket_name_gcs, object_name = input_video_url[5:].split('/', 1)
        bucket = storage_client.bucket(bucket_name_gcs)
        blob = bucket.blob(object_name)
    except (ValueError, Exception) as e:
        print(f"Error parsing GCS URL or initializing client: {e}")
        return

    temp_video_file_path = None
    try:
        with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as temp_video_file:
            temp_video_file_path = temp_video_file.name
            blob.download_to_filename(temp_video_file_path)

            subprocess.run([
                "ffmpeg", "-y", "-i", temp_video_file_path,
                "-ss", start, "-to", end,
                "-c", "copy", output_file
            ], check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        print(f"FFmpeg error: {e.stderr}")
    except FileNotFoundError:
        print("Error: ffmpeg command not found. Please ensure FFmpeg is installed and in your PATH.")
    except Exception as e:
        print(f"An unexpected error occurred during video clip creation: {e}")
    finally:
        if temp_video_file_path and os.path.exists(temp_video_file_path):
            try:
                os.remove(temp_video_file_path)
            except OSError as e:
                print(f"Error removing temporary file {temp_video_file_path}: {e}")

if __name__ == '__main__':  
    print(f"Starting Flask app for project: {GOOGLE_CLOUD_PROJECT}, bucket: {bucket_name}")
    app.run(debug=True, host='0.0.0.0', port=int(os.environ.get('PORT', 8082)))