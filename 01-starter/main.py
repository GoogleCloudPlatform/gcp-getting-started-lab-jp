"""
Restaurant Agent - Entry Point

Run the web server:
    python main.py
"""
from web.app import app

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=8000)
