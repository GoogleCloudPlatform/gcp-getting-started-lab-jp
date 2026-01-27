"""
Restaurant Agent - Entry Point

Run the web server:
    python main.py

Or with uvicorn directly:
    uvicorn web.app:app --reload --host 0.0.0.0 --port 8000
"""
import uvicorn

from web.app import app

if __name__ == "__main__":
    uvicorn.run("web.app:app", reload=True, host="0.0.0.0", port=8000)
