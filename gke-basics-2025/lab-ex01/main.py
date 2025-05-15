from flask import Flask, render_template_string

app = Flask(__name__)

@app.route('/')
def index():
    template = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>GKE Dojo Handson 2023</title>
        <style>
            body {
                display: flex;
                justify-content: center;
                align-items: center;
                height: 100vh;
                background-color: #282c34;
                color: #61dafb;
                font-family: Arial, sans-serif;
                font-size: 3em;
            }
        </style>
    </head>
    <body>
        <div>
            Welcome to <span style="border-bottom: 3px solid #61dafb;">gke-dojo 2025</span>
        </div>
    </body>
    </html>
    """

    return render_template_string(template)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
