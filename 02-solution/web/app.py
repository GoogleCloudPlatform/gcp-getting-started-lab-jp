"""
Flask Web Application for the Restaurant Agent.

This file provides the web interface for users to interact with the agent.
It handles user sessions, chat messages, and communicates with the ADK agent.
"""
import asyncio
import logging
import os
import json
import uuid
from queue import Queue
from datetime import datetime
import markdown
from flask import (
    Flask,
    Response,
    redirect,
    render_template,
    request,
    session,
    url_for,
    jsonify,
)

from agent import root_agent
from agent.runner import RestaurantRunner

app = Flask(__name__)
app.secret_key = os.urandom(24)

# In-memory storage for user sessions
user_sessions = {}

# --- Logging Setup for SSE ---
log_queue = Queue()


class QueueHandler(logging.Handler):
    def __init__(self, queue):
        super().__init__()
        self.queue = queue

    def emit(self, record):
        self.queue.put(record)


# Get the root logger
root_logger = logging.getLogger()
root_logger.setLevel(logging.INFO)

# Create a handler that writes to the queue
queue_handler = QueueHandler(log_queue)
root_logger.addHandler(queue_handler)


@app.route('/stream-logs')
def stream_logs():
    def generate():
        formatter = logging.Formatter('%(asctime)s')
        while True:
            record = log_queue.get()
            log_entry = {
                'timestamp': formatter.formatTime(record, "%Y-%m-%d %H:%M:%S"),
                'name': record.name,
                'levelname': record.levelname,
                'message': record.getMessage()
            }
            yield f"data: {json.dumps(log_entry)}\n\n"
    return Response(generate(), mimetype='text/event-stream')


@app.route('/', methods=['GET', 'POST'])
def index():
    """Landing page where users enter their username."""
    if request.method == 'POST':
        username = request.form.get('username')
        if username:
            session['username'] = username
            return redirect(url_for('chat'))
    return render_template('index.html')


@app.route('/chat')
def chat():
    """Main chat interface."""
    if 'username' not in session:
        return redirect(url_for('index'))

    username = session['username']

    # Initialize user's session list if not exists
    if username not in user_sessions:
        user_sessions[username] = {}

    # Get or create current session
    current_session_id = session.get('current_chat_session')
    if not current_session_id or current_session_id not in user_sessions[username]:
        current_session_id = str(uuid.uuid4())
        user_sessions[username][current_session_id] = {
            'id': current_session_id,
            'name': 'Session 1',
            'created_at': datetime.now().isoformat(),
            'agent_session_id': None,
            'messages': []
        }
        session['current_chat_session'] = current_session_id

    sessions_list = list(user_sessions[username].values())
    sessions_list.sort(key=lambda x: x['created_at'], reverse=True)
    current_session = user_sessions[username][current_session_id]

    return render_template(
        'chat.html',
        username=username,
        sessions=sessions_list,
        current_session=current_session
    )


@app.route('/sessions/new', methods=['POST'])
def create_session():
    """Create a new chat session."""
    if 'username' not in session:
        return jsonify({'error': 'Not authenticated'}), 401

    username = session['username']
    if username not in user_sessions:
        user_sessions[username] = {}

    session_num = len(user_sessions[username]) + 1
    new_session_id = str(uuid.uuid4())

    user_sessions[username][new_session_id] = {
        'id': new_session_id,
        'name': f'Session {session_num}',
        'created_at': datetime.now().isoformat(),
        'agent_session_id': None,
        'messages': []
    }

    session['current_chat_session'] = new_session_id

    return jsonify({
        'session': user_sessions[username][new_session_id],
        'message': 'New session created. Memory Bank data is still available!'
    })


@app.route('/sessions/<session_id>/switch', methods=['POST'])
def switch_session(session_id):
    """Switch to a different chat session."""
    if 'username' not in session:
        return jsonify({'error': 'Not authenticated'}), 401

    username = session['username']
    if username not in user_sessions or session_id not in user_sessions[username]:
        return jsonify({'error': 'Session not found'}), 404

    session['current_chat_session'] = session_id
    chat_session = user_sessions[username][session_id]

    return jsonify({
        'session': chat_session,
        'messages': chat_session['messages']
    })


@app.route('/sessions/<session_id>', methods=['DELETE'])
def delete_session(session_id):
    """Delete a chat session."""
    if 'username' not in session:
        return jsonify({'error': 'Not authenticated'}), 401

    username = session['username']
    if username not in user_sessions or session_id not in user_sessions[username]:
        return jsonify({'error': 'Session not found'}), 404

    del user_sessions[username][session_id]

    if session.get('current_chat_session') == session_id:
        if user_sessions[username]:
            session['current_chat_session'] = list(user_sessions[username].keys())[0]
        else:
            session.pop('current_chat_session', None)

    return jsonify({'message': 'Session deleted'})


@app.route('/ask', methods=['POST'])
def ask():
    """Handle user messages and get agent responses."""
    if 'username' not in session:
        return jsonify({'error': 'Not authenticated'}), 401

    user_message = request.json.get('message')
    if not user_message:
        return jsonify({'error': 'No message provided'}), 400

    username = session['username']
    current_session_id = session.get('current_chat_session')
    chat_session = user_sessions[username].get(current_session_id)

    if not chat_session:
        return jsonify({'error': 'Session not found'}), 404

    agent_session_id = chat_session.get('agent_session_id')

    try:
        # Create RestaurantRunner instance
        runner = RestaurantRunner(
            agent=root_agent,
            user_id=username,
            session_id=agent_session_id
        )

        # Call the agent and get response
        agent_response_md = asyncio.run(runner.call_agent(user_message))
        agent_response_html = markdown.markdown(agent_response_md or "No response from agent.")

        # Store messages in our session
        chat_session['messages'].append({
            'role': 'user',
            'content': user_message,
            'timestamp': datetime.now().isoformat()
        })
        chat_session['messages'].append({
            'role': 'agent',
            'content': agent_response_html,
            'timestamp': datetime.now().isoformat()
        })

        # Update the agent session ID in our chat session
        if runner._session_id:
            chat_session['agent_session_id'] = runner._session_id

        return jsonify({'agent_response': agent_response_html})

    except Exception as e:
        logging.error(f"Error calling agent: {e}", exc_info=True)
        return jsonify({'error': str(e)}), 500


if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=8080)
