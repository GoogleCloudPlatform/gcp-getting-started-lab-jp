import os
import streamlit as st
import requests
from google.auth.transport.requests import Request
from google.oauth2.id_token import fetch_id_token

# 環境変数から backend の URL を取得
BACKEND_URL = os.environ.get("BACKEND_URL", "http://backend:8080")  # デフォルト値は適宜変更

def get_start_end_seconds(timestamp):
  """04:57-05:58 のような形式のタイムスタンプを受け取り、
  開始秒と終了秒をタプルで返す
  """
  start, end = timestamp.split('-')
  start_seconds = int(start.split(':')[0]) * 60 + int(start.split(':')[1])
  end_seconds = int(end.split(':')[0]) * 60 + int(end.split(':')[1])
  return start_seconds, end_seconds

def make_request(endpoint: str, params: dict = None):
    """Backend API に認証情報を付与してリクエストを送信する"""
    auth_req = Request()
    id_token = fetch_id_token(auth_req, BACKEND_URL)
    headers = {'Authorization': f'Bearer {id_token}'}
    response = requests.get(f"{BACKEND_URL}/{endpoint}", params=params, headers=headers)
    response.raise_for_status()  # ステータスコードがエラーの場合は例外を発生させる
    return response.json()

# トグル表示の選択肢
search_option = st.selectbox("Search Option", ("File Search", "Scene Search"))

if search_option == "File Search":
    st.write("# File Search")
    file_search_query = st.text_input("Search Query", key="file_search")
    if st.button("Search", key="file_search_button"):
        st.write(f"Searching for: {file_search_query}")
        if file_search_query:
            try:
                results = make_request("file_search", params={'q': file_search_query})['results']
                if results:
                    st.write("## Result")
                    for c, result in enumerate(results):
                        if c == 0:
                            st.write(result['summary'])
                            continue
                        st.write(f"Video ID: {result['id']}")
                        st.write(f"Title: {result['title']}")
                        st.video(result['signed_url'])
                        st.divider()
                else:
                    st.write("No results found.")
            except requests.exceptions.RequestException as e:
                st.error(f"An error occurred while searching: {e}")

elif search_option == "Scene Search":
    st.write("# Scene Search")
    
    # Search Query と Top N を並列に表示
    col1, col2 = st.columns((7,1))
    with col1:
        scene_search_query = st.text_input("Search Query", key="scene_search")
    with col2:
        top_n = st.number_input(
            "Top N", 
            min_value=1, 
            max_value=3, 
            value=1,
            help="Top N とは ... シーンの検索対象最大動画数"
                 "\n\n"
                 "まず検索文の回答に適した動画が全動画を対象に検索され\n"
                 "その後、上位 N 個の動画からシーンが検索されます。"
        )

    if st.button("Search", key="scene_search_button"):
        st.write(f"Searching for: {scene_search_query}")
        if scene_search_query:
            try:
                results = make_request("scene_search", params={'q': scene_search_query, 'top_n': top_n})['results']
                if results:
                    st.write("## Result")
                    for c, result in enumerate(results):
                        video_id = c + 1
                        st.write(f"Video ID: {video_id}")
                        st.write(f"Title: {result['title']}")
                        st.write(f"Description: {result['Description']}")
                        st.write(f"Timestamp: {result['Timestamp']}")
                        start_time, end_time = get_start_end_seconds(result['Timestamp'])
                        signed_url = result['signed_url']
                        st.video(signed_url, start_time=start_time, end_time=end_time)
                        st.divider()
                else:
                    st.write("No results found.")
            except requests.exceptions.RequestException as e:
                st.error(f"An error occurred while searching: {e}")
