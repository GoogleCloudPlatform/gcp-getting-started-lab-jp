import streamlit as st
import requests
import os

# --- 環境変数から Backend URL を取得 ---
BACKEND_URL = os.environ.get("BACKEND_URL", "http://backend:8080")

# --- Backend URL ハードコード ver (ローカル検証用) ---
# BACKEND_URL = "https://backend2-608635780090.asia-northeast1.run.app"

# --- Streamlit アプリケーションの設定 ---
st.title("動画検索アプリケーション")

# --- ファイル検索 ---
st.header("ファイル検索")
query = st.text_input("検索キーワード")
if st.button("検索"):
    if query:
        response = requests.get(f"{BACKEND_URL}/file_search?q={query}")
        if response.status_code == 200:
            results = response.json()
            st.write(results["results"][0]["summary"])
            for r in results["results"][1:]:
                st.write(f"## {r['title']}")
                st.video(r["signed_url"]) 
        else:
            st.error("エラーが発生しました。")
    else:
        st.warning("検索キーワードを入力してください。")