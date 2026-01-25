document.addEventListener('DOMContentLoaded', () => {
    const chatForm = document.getElementById('chat-form');
    const messageInput = document.getElementById('message-input');
    const chatMessages = document.getElementById('chat-messages');
    const logContent = document.getElementById('log-content');
    const newSessionBtn = document.getElementById('new-session-btn');
    const sessionList = document.getElementById('session-list');

    // --- SSE for Log Streaming ---
    const logSource = new EventSource('/stream-logs');

    logSource.onmessage = function(event) {
        try {
            const logEntry = JSON.parse(event.data);
            displayLogEntry(logEntry);
        } catch (e) {
            console.error('Error parsing log entry:', e, event.data);
            logContent.prepend(createLogElement({
                levelname: 'ERROR',
                message: 'Failed to parse log entry: ' + event.data
            }));
        }
    };

    logSource.onerror = function(err) {
        console.error('EventSource failed:', err);
        logContent.prepend(createLogElement({
            levelname: 'ERROR',
            message: 'Log stream disconnected.'
        }));
    };

    const waitingAnimation = document.querySelector('.waiting-animation');

    // --- Chat Form Submission ---
    chatForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        const message = messageInput.value.trim();
        if (!message) return;

        appendMessage(message, 'user-message', true);
        messageInput.value = '';

        waitingAnimation.style.display = 'flex';
        waitingAnimation.style.pointerEvents = 'auto';
        waitingAnimation.style.opacity = 1;

        try {
            const response = await fetch('/ask', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ message })
            });

            const data = await response.json();

            if (data.error) {
                appendMessage(`Error: ${data.error}`, 'agent-message', true);
            } else {
                appendMessage(data.agent_response, 'agent-message', false);
            }

        } catch (error) {
            console.error('Error:', error);
            appendMessage('An error occurred while communicating with the agent.', 'agent-message', true);
        } finally {
            waitingAnimation.style.opacity = 0;
            waitingAnimation.style.pointerEvents = 'none';
            setTimeout(() => {
                waitingAnimation.style.display = 'none';
            }, 300);
        }
    });

    // --- New Session Button ---
    newSessionBtn.addEventListener('click', async () => {
        try {
            const response = await fetch('/sessions/new', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                }
            });

            const data = await response.json();

            if (data.error) {
                alert('Error creating session: ' + data.error);
            } else {
                // Show notification about memory bank
                showNotification(data.message);
                // Reload page to show new session
                window.location.reload();
            }
        } catch (error) {
            console.error('Error creating session:', error);
            alert('Failed to create new session');
        }
    });

    // --- Session Switching ---
    sessionList.addEventListener('click', async (e) => {
        const sessionItem = e.target.closest('.session-item');
        const deleteBtn = e.target.closest('.delete-session-btn');

        if (deleteBtn) {
            e.stopPropagation();
            const sessionId = deleteBtn.dataset.sessionId;
            if (confirm('Delete this session? Memory Bank data will be preserved.')) {
                await deleteSession(sessionId);
            }
            return;
        }

        if (sessionItem && !sessionItem.classList.contains('active')) {
            const sessionId = sessionItem.dataset.sessionId;
            await switchSession(sessionId);
        }
    });

    async function switchSession(sessionId) {
        try {
            const response = await fetch(`/sessions/${sessionId}/switch`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                }
            });

            const data = await response.json();

            if (data.error) {
                alert('Error switching session: ' + data.error);
            } else {
                window.location.reload();
            }
        } catch (error) {
            console.error('Error switching session:', error);
            alert('Failed to switch session');
        }
    }

    async function deleteSession(sessionId) {
        try {
            const response = await fetch(`/sessions/${sessionId}`, {
                method: 'DELETE',
                headers: {
                    'Content-Type': 'application/json'
                }
            });

            const data = await response.json();

            if (data.error) {
                alert('Error deleting session: ' + data.error);
            } else {
                window.location.reload();
            }
        } catch (error) {
            console.error('Error deleting session:', error);
            alert('Failed to delete session');
        }
    }

    function showNotification(message) {
        const notification = document.createElement('div');
        notification.className = 'notification';
        notification.innerHTML = `
            <span class="notification-icon">&#128161;</span>
            <span>${message}</span>
        `;
        notification.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            background: #2ecc71;
            color: white;
            padding: 15px 25px;
            border-radius: 8px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.2);
            z-index: 1000;
            animation: slideIn 0.3s ease;
        `;
        document.body.appendChild(notification);

        setTimeout(() => {
            notification.remove();
        }, 3000);
    }

    function appendMessage(message, className, isText) {
        const messageElement = document.createElement('div');
        messageElement.classList.add('message', className);
        if (isText) {
            messageElement.textContent = message;
        } else {
            messageElement.innerHTML = message;
        }
        chatMessages.appendChild(messageElement);
        chatMessages.scrollTop = chatMessages.scrollHeight;
    }

    function createLogElement(logEntry) {
        const logDiv = document.createElement('div');
        logDiv.classList.add('log-entry', `log-${logEntry.levelname.toLowerCase()}`);

        const timestampSpan = document.createElement('span');
        timestampSpan.classList.add('log-timestamp');
        timestampSpan.textContent = logEntry.timestamp;

        const levelSpan = document.createElement('span');
        levelSpan.classList.add('log-level');
        levelSpan.textContent = `[${logEntry.levelname}]`;

        const nameSpan = document.createElement('span');
        nameSpan.classList.add('log-name');
        nameSpan.textContent = `(${logEntry.name})`;

        const messageSpan = document.createElement('span');
        messageSpan.classList.add('log-message');
        messageSpan.textContent = logEntry.message;

        logDiv.appendChild(timestampSpan);
        logDiv.appendChild(levelSpan);
        logDiv.appendChild(nameSpan);
        logDiv.appendChild(document.createTextNode(' '));
        logDiv.appendChild(messageSpan);

        return logDiv;
    }

    function displayLogEntry(logEntry) {
        const newLogElement = createLogElement(logEntry);
        if (logContent.firstChild) {
            logContent.insertBefore(newLogElement, logContent.firstChild);
        } else {
            logContent.appendChild(newLogElement);
        }
        logContent.scrollTop = 0;
    }

    // Scroll to bottom on load
    chatMessages.scrollTop = chatMessages.scrollHeight;
});
