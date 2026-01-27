"""
FastAPI Web Application for the Restaurant Agent.

This file provides the web interface for users to interact with the agent.
It handles user sessions, chat messages, and communicates with the ADK agent.
"""
import logging
import os
import uuid
from datetime import datetime
from typing import Optional

import markdown
from fastapi import FastAPI, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel
from starlette.middleware.sessions import SessionMiddleware

from agent import root_agent
from agent.runner import RestaurantRunner

app = FastAPI(title="Restaurant Agent")
app.add_middleware(SessionMiddleware, secret_key=os.urandom(24).hex())

# Mount static files and templates
app.mount("/static", StaticFiles(directory="web/static"), name="static")
templates = Jinja2Templates(directory="web/templates")

# In-memory storage for user sessions
user_sessions: dict = {}


# Pydantic models for request/response
class MessageRequest(BaseModel):
    message: str


@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    """Landing page where users enter their username."""
    return templates.TemplateResponse("index.html", {"request": request})


@app.post("/")
async def login(request: Request, username: str = Form(...)):
    """Handle login form submission."""
    request.session["username"] = username
    return RedirectResponse(url="/chat", status_code=303)


@app.get("/chat", response_class=HTMLResponse)
async def chat(request: Request):
    """Main chat interface."""
    username = request.session.get("username")
    if not username:
        return RedirectResponse(url="/", status_code=303)

    # Initialize user's session list if not exists
    if username not in user_sessions:
        user_sessions[username] = {}

    # Get or create current session
    current_session_id = request.session.get("current_chat_session")
    if not current_session_id or current_session_id not in user_sessions[username]:
        current_session_id = str(uuid.uuid4())
        user_sessions[username][current_session_id] = {
            "id": current_session_id,
            "name": "Session 1",
            "created_at": datetime.now().isoformat(),
            "agent_session_id": None,
            "messages": []
        }
        request.session["current_chat_session"] = current_session_id

    sessions_list = list(user_sessions[username].values())
    sessions_list.sort(key=lambda x: x["created_at"], reverse=True)
    current_session = user_sessions[username][current_session_id]

    return templates.TemplateResponse(
        "chat.html",
        {
            "request": request,
            "username": username,
            "sessions": sessions_list,
            "current_session": current_session
        }
    )


@app.post("/sessions/new")
async def create_session(request: Request):
    """Create a new chat session."""
    username = request.session.get("username")
    if not username:
        raise HTTPException(status_code=401, detail="Not authenticated")

    if username not in user_sessions:
        user_sessions[username] = {}

    session_num = len(user_sessions[username]) + 1
    new_session_id = str(uuid.uuid4())

    user_sessions[username][new_session_id] = {
        "id": new_session_id,
        "name": f"Session {session_num}",
        "created_at": datetime.now().isoformat(),
        "agent_session_id": None,
        "messages": []
    }

    request.session["current_chat_session"] = new_session_id

    return {
        "session": user_sessions[username][new_session_id],
        "message": "New session created. Memory Bank data is still available!"
    }


@app.post("/ask")
async def ask(request: Request, body: MessageRequest):
    """Handle user messages and get agent responses."""
    username = request.session.get("username")
    if not username:
        raise HTTPException(status_code=401, detail="Not authenticated")

    user_message = body.message
    if not user_message:
        raise HTTPException(status_code=400, detail="No message provided")

    current_session_id = request.session.get("current_chat_session")
    chat_session = user_sessions.get(username, {}).get(current_session_id)

    if not chat_session:
        raise HTTPException(status_code=404, detail="Session not found")

    agent_session_id = chat_session.get("agent_session_id")

    try:
        # TODO: Create RestaurantRunner instance
        # The runner should be created with:
        # - agent=root_agent
        # - user_id=username
        # - session_id=agent_session_id (can be None for new sessions)
        # REPLACE_CREATE_RUNNER
        runner = None  # REPLACE THIS

        # TODO: Call the agent and get response
        # Use await runner.call_agent(user_message) to get the response
        # Convert the markdown response to HTML using markdown.markdown()
        # REPLACE_CALL_AGENT
        agent_response_html = "TODO: Implement agent call"  # REPLACE THIS

        # Store messages in our session
        chat_session["messages"].append({
            "role": "user",
            "content": user_message,
            "timestamp": datetime.now().isoformat()
        })
        chat_session["messages"].append({
            "role": "agent",
            "content": agent_response_html,
            "timestamp": datetime.now().isoformat()
        })

        # Update the agent session ID in our chat session
        if runner and runner._session_id:
            chat_session["agent_session_id"] = runner._session_id

        return {"agent_response": agent_response_html}

    except Exception as e:
        logging.error(f"Error calling agent: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
