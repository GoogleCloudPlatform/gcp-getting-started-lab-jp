export class VoicecallBackendAPI {
  constructor(backendUrl) {
    this.backendUrl = backendUrl;

    this.onReceiveResponse = (message) => {  // callback setup later
      console.log("Default message received callback", message);
    };
    this.onConnectionClosed = () => {};      // callback setup later

    this.webSocket = null;
  }

  // status checker
  isConnected() {
    if (this.webSocket === null) return false;
    if (this.webSocket.readyState === 1) return true;
    return false;
  }

  isClosed() {
    if (this.webSocket === null) return true;
    if (this.webSocket.readyState === 2) return true;
    if (this.webSocket.readyState === 3) return true;
    return false;
  }

  // connect and disconnect
  connect() {
    console.log("connecting: ", this.backendUrl);

    this.webSocket = new WebSocket(this.backendUrl);

    this.webSocket.onclose = (event) => {
      console.log("websocket closed: ", event);
      this.onConnectionClosed();
    };

    this.webSocket.onerror = (event) => {
      console.log("websocket error: ", event);
    };

    this.webSocket.onmessage = this.onReceiveMessage.bind(this);
  }

  disconnect() {
    if (this.webSocket === null) return;
    this.webSocket.close();
  }

  // receive a message
  onReceiveMessage(messageEvent) {
    console.log("Message received: ", messageEvent);
    const messageData = JSON.parse(messageEvent.data);
    this.onReceiveResponse(messageData);
  }

  // send a message
  sendMessage(message) {
    if (this.webSocket === null) return;
    this.webSocket.send(JSON.stringify(message));
  }

  sendAudioMessage(base64PCM) {
    const message = {
      type: 'audio',
      data: base64PCM,
      mime_type: 'audio/pcm',
    };
    this.sendMessage(message);
  }
}
