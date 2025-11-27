import { useState, useRef, useEffect } from "react";
import ReactMarkdown from 'react-markdown';
import { VoicecallBackendAPI } from "lib/voicecall-backend";
import {
  LiveAudioInputManager,
  LiveAudioOutputManager
} from "lib/live-audio-manager";


// ===== Toast Notification Component =====
const ToastNotification = ({ message, type, isVisible, onClose }) => {
  if (!isVisible) return null;

  const bgGradient = type === 'error'
    ? 'bg-gradient-to-r from-red-500 to-red-600'
    : type === 'success'
      ? 'bg-gradient-to-r from-green-500 to-emerald-600'
      : 'bg-gradient-to-r from-blue-500 to-indigo-600';
  const icon = type === 'error' ? '❌' : type === 'success' ? '✅' : 'ℹ️';

  return (
    <div className="fixed top-4 right-4 z-50 animate-fade-in-down">
      <div className={`${bgGradient} text-white px-6 py-4 rounded-xl shadow-2xl flex items-center space-x-3 max-w-md transform hover:scale-105 transition-all duration-300`}>
        <span className="text-2xl">{icon}</span>
        <p className="text-sm font-medium flex-1">{message}</p>
        <button
          onClick={onClose}
          className="text-white/80 hover:text-white transition-colors ml-2 hover:rotate-90 transform duration-200"
        >
          ✕
        </button>
      </div>
    </div>
  );
};

// ===== Loading Indicator Component =====
const LoadingIndicator = ({ message, isVisible }) => {
  if (!isVisible) return null;

  return (
    <div className="fixed inset-0 bg-black/40 backdrop-blur-md flex items-center justify-center z-40 animate-fade-in">
      <div className="bg-white/95 backdrop-blur-xl rounded-3xl shadow-2xl p-10 flex flex-col items-center space-y-5 border border-white/20 transform animate-scale-in">
        <div className="relative">
          <div className="animate-spin rounded-full h-16 w-16 border-4 border-purple-200"></div>
          <div className="animate-spin rounded-full h-16 w-16 border-t-4 border-purple-600 absolute top-0 left-0"></div>
        </div>
        <p className="text-slate-700 font-semibold text-lg">{message}</p>
      </div>
    </div>
  );
};

// ===== Image Zoom Modal Component =====
const ImageZoomModal = ({ imageUrl, onClose }) => {
  if (!imageUrl) return null;

  return (
    <div
      className="fixed inset-0 bg-black/90 backdrop-blur-sm flex items-center justify-center z-50 p-4 animate-fade-in"
      onClick={onClose}
    >
      <button
        onClick={onClose}
        className="absolute top-4 right-4 text-white/80 hover:text-white text-4xl font-light transition-colors hover:rotate-90 transform duration-300"
      >
        ✕
      </button>
      <img
        src={imageUrl}
        alt="Zoomed"
        className="max-w-[90%] max-h-[90%] object-contain rounded-lg shadow-2xl animate-scale-in"
        onClick={(e) => e.stopPropagation()}
      />
    </div>
  );
};

/**
 * 【ハンズオン教材】Technical Support Agent
 * 
 * このコンポーネントは以下の機能を提供します：
 * 1. Gemini Live APIとのWebSocket接続
 * 2. リアルタイム音声入出力管理
 * 3. 画像・動画のアップロードと送信
 * 4. テクニカルサポート向けUI
 */
// ===== Ticket Modal Component =====
const TicketModal = ({ isOpen, onClose, ticketData }) => {
  if (!isOpen || !ticketData) return null;

  return (
    <div className="fixed inset-0 bg-black/50 backdrop-blur-sm flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-2xl shadow-2xl max-w-md w-full overflow-hidden transform transition-all scale-100">
        {/* Header */}
        <div className="bg-blue-600 p-6 text-white">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-xl font-bold flex items-center">
              <span className="text-2xl mr-2">🎫</span> サポートチケット作成
            </h3>
            <button
              onClick={onClose}
              className="text-white/80 hover:text-white transition-colors"
            >
              ✕
            </button>
          </div>
          <p className="text-blue-100 text-sm">
            以下の内容でチケットが発行されました
          </p>
        </div>

        {/* Body */}
        <div className="p-6 space-y-4">
          <div>
            <label className="text-xs font-bold text-slate-400 uppercase tracking-wider">チケットID (Ticket ID)</label>
            <div className="text-2xl font-mono font-bold text-slate-800 mt-1 select-all">
              {ticketData.ticket_id}
            </div>
          </div>

          <div>
            <label className="text-xs font-bold text-slate-400 uppercase tracking-wider">タイトル (Title)</label>
            <div className="text-2xl font-mono font-bold text-slate-800 mt-1 select-all">
              {ticketData.title}
            </div>
          </div>

          <div>
            <label className="text-xs font-bold text-slate-400 uppercase tracking-wider">概要 (Summary)</label>
            <div className="text-slate-700 font-medium mt-1 bg-slate-50 p-3 rounded-lg border border-slate-200">
              {ticketData.summary}
            </div>
          </div>

          <div>
            <label className="text-xs font-bold text-slate-400 uppercase tracking-wider">優先度 (Priority)</label>
            <div className="mt-1">
              <span className={`inline-flex items-center px-3 py-1 rounded-full text-sm font-medium ${ticketData.priority === 'Urgent' ? 'bg-red-100 text-red-800' :
                ticketData.priority === 'High' ? 'bg-orange-100 text-orange-800' :
                  'bg-blue-100 text-blue-800'
                }`}>
                {ticketData.priority}
              </span>
            </div>
          </div>
        </div>

        {/* Footer */}
        <div className="p-6 bg-slate-50 border-t border-slate-100 flex justify-end">
          <button
            onClick={onClose}
            className="bg-blue-600 hover:bg-blue-700 text-white font-bold py-2 px-6 rounded-lg shadow-md transition-colors"
          >
            閉じる
          </button>
        </div>
      </div>
    </div>
  );
};

/**
 * 【ハンズオン教材】Technical Support Agent
 * 
 * このコンポーネントは以下の機能を提供します：
 * 1. Gemini Live APIとのWebSocket接続
 * 2. リアルタイム音声入出力管理
 * 3. 画像・動画のアップロードと送信
 * 4. テクニカルサポート向けUI
 */
export default function VoiceClient() {

  // ===== 基本設定とユーティリティ =====
  const sleep = (time) => new Promise((r) => setTimeout(r, time));
  const BACKEND_URL = process.env.NEXT_PUBLIC_BACKEND_URL;

  // ===== 状態管理 =====
  const [connectionStatus, setConnectionStatus] = useState("disconnected"); // "disconnected" | "connected"
  const [micStatus, setMicStatus] = useState("off"); // "on" | "off"
  const [buttonDisabled, setButtonDisabled] = useState(false);
  const [transcriptions, setTranscriptions] = useState([]); // トランスクリプション履歴
  const [uploadStatus, setUploadStatus] = useState(""); // アップロード状態メッセージ

  // Modal State
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [ticketData, setTicketData] = useState(null);

  // Image Zoom Modal State
  const [zoomImage, setZoomImage] = useState(null);

  // Toast Notification State
  const [toastMessage, setToastMessage] = useState("");
  const [toastType, setToastType] = useState("info"); // "info" | "error" | "success"
  const [showToast, setShowToast] = useState(false);

  // Loading State
  const [isLoading, setIsLoading] = useState(false);
  const [loadingMessage, setLoadingMessage] = useState("");

  // ===== ユニークID生成用 =====
  const transcriptionIdRef = useRef(0);
  const generateUniqueId = () => {
    transcriptionIdRef.current += 1;
    return `transcription_${Date.now()}_${transcriptionIdRef.current}`;
  };

  // ===== 自動スクロール用参照 =====
  const transcriptionsEndRef = useRef(null);

  // ===== API・音声管理のセットアップ =====
  const _voicecallApi = useRef(new VoicecallBackendAPI(BACKEND_URL));
  const voicecallApi = _voicecallApi.current;

  const _liveAudioOutputManager = useRef();
  const _liveAudioInputManager = useRef();
  const liveAudioOutputManager = _liveAudioOutputManager.current;
  const liveAudioInputManager = _liveAudioInputManager.current;

  // 音声管理ライブラリの初期化
  useEffect(() => {
    _liveAudioInputManager.current = new LiveAudioInputManager();
    _liveAudioOutputManager.current = new LiveAudioOutputManager();
  }, []);

  // Toast自動非表示
  useEffect(() => {
    if (showToast) {
      const timer = setTimeout(() => {
        setShowToast(false);
      }, 4000);
      return () => clearTimeout(timer);
    }
  }, [showToast]);

  // ===== ユーティリティ関数 =====

  // トースト通知を表示
  const showToastNotification = (message, type = "info") => {
    setToastMessage(message);
    setToastType(type);
    setShowToast(true);
  };

  // 会話履歴をエクスポート
  const exportTranscriptions = () => {
    if (transcriptions.length === 0) {
      showToastNotification("エクスポートする履歴がありません", "error");
      return;
    }

    const content = transcriptions.map(t => {
      const speaker = t.type === 'input' ? 'User' : t.type === 'output' ? 'Sarah' : 'System';
      return `[${t.timestamp.toLocaleString()}] ${speaker}:\n${t.text}\n`;
    }).join('\n---\n\n');

    const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `support-history-${new Date().toISOString().slice(0, 10)}.txt`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);

    showToastNotification("履歴をダウンロードしました", "success");
  };



  // ===== 音声入出力の制御 =====

  // 接続状態変化時の音声入力制御
  useEffect(() => {
    if (connectionStatus == "connected") {
      startAudioInput(); // マイクへのアクセス開始
      setMicStatus("off"); // 初期状態はマイクオフ
      setTranscriptions([]); // トランスクリプション履歴をクリア
      transcriptionIdRef.current = 0; // IDカウンターをリセット
    } else {
      stopAudioStream(); // 音声ストリーミング停止
      stopAudioInput(); // マイクアクセス停止
    }
  }, [connectionStatus]);

  // マイク状態変化時の音声ストリーミング制御
  useEffect(() => {
    if (micStatus == "on") {
      startAudioStream(); // 音声データ送信開始
    } else {
      const _stopAudioStream = async () => {
        await sleep(2000); // 音声データ送信完了まで待機
        stopAudioStream();
      };
      _stopAudioStream();
    }
  }, [micStatus]);

  // トランスクリプション追加時の自動スクロール
  useEffect(() => {
    if (transcriptionsEndRef.current) {
      transcriptionsEndRef.current.scrollIntoView({
        behavior: 'smooth',
        block: 'nearest'
      });
    }
  }, [transcriptions]);

  // マイクアクセス開始
  const startAudioInput = async () => {
    if (!liveAudioInputManager) return;
    try {
      await liveAudioInputManager.connectMicrophone();
    } catch (error) {
      console.error("マイクアクセスエラー:", error);
      showToastNotification("マイクへのアクセスが拒否されました。ブラウザの設定を確認してください。", "error");
    }
  };

  // マイクアクセス停止
  const stopAudioInput = async () => {
    if (!liveAudioInputManager) return;
    await liveAudioInputManager.disconnectMicrophone();
  };

  // 音声データストリーミング開始
  const startAudioStream = () => {
    if (!voicecallApi.isConnected) return;
    liveAudioInputManager.onNewAudioRecordingChunk = (audioData) => {
      // console.log("音声データを送信中...");
      voicecallApi.sendAudioMessage(audioData);
    };
  }

  // 音声データストリーミング停止
  const stopAudioStream = () => {
    if (!liveAudioInputManager) return;
    liveAudioInputManager.onNewAudioRecordingChunk = () => { };
  }

  // ===== WebSocket接続制御 =====

  // バックエンドへの接続開始
  const connectToBackend = async () => {
    setButtonDisabled(true);
    setIsLoading(true);
    setLoadingMessage("Sarahに接続中...");

    try {
      voicecallApi.connect();

      // 接続完了まで待機
      while (!voicecallApi.isConnected()) {
        await sleep(500);
        if (voicecallApi.isClosed()) {
          showToastNotification("接続に失敗しました。バックエンドが起動しているか確認してください。", "error");
          disconnectFromBackend();
          return;
        }
      }

      setButtonDisabled(false);
      setConnectionStatus("connected");
      showToastNotification("Sarahに接続しました", "success");
    } catch (error) {
      console.error("接続エラー:", error);
      showToastNotification("接続エラーが発生しました", "error");
      setButtonDisabled(false);
    } finally {
      setIsLoading(false);
      setLoadingMessage("");
    }
  };

  // バックエンドからの切断
  const disconnectFromBackend = async () => {
    setButtonDisabled(true);
    await voicecallApi.disconnect();
    await sleep(500);
    setButtonDisabled(false);
    setConnectionStatus("disconnected");

    // サポート履歴をクリア
    setTranscriptions([]);
    transcriptionIdRef.current = 0;
  };

  // ===== 音声応答の受信処理 =====
  voicecallApi.onReceiveResponse = (messageResponse) => {
    if (messageResponse.type == "audio") {
      // console.log("音声応答を受信しました");
      const audioChunk = messageResponse.data;
      liveAudioOutputManager.playAudioChunk(audioChunk);
    } else if (messageResponse.type == "input_transcription") {
      // ユーザーの音声入力の文字起こし
      console.log("音声入力テキスト:", messageResponse.text);
      const text = messageResponse.text.trim();
      setTranscriptions(prev => [...prev, {
        id: generateUniqueId(),
        text: text,
        timestamp: new Date(),
        type: 'input'
      }]);
    } else if (messageResponse.type == "output_transcription") {
      // AI音声応答の文字起こし
      console.log("音声出力テキスト:", messageResponse.text);
      const text = messageResponse.text.trim();
      setTranscriptions(prev => [...prev, {
        id: generateUniqueId(),
        text: text,
        timestamp: new Date(),
        type: 'output'
      }]);
    } else if (messageResponse.type == "ticket_created") {
      // チケット作成通知
      console.log("チケット作成:", messageResponse.data);
      const { ticket_id, title, summary, priority } = messageResponse.data;

      // モーダルを表示
      setTicketData(messageResponse.data);
      setIsModalOpen(true);

      // ログにも残す
      setTranscriptions(prev => [...prev, {
        id: generateUniqueId(),
        text: `🎫 サポートチケットを作成しました\nID: ${ticket_id}\nタイトル: ${title}\n概要: ${summary}\n優先度: ${priority}`,
        timestamp: new Date(),
        type: 'system'
      }]);
    }
  };

  // ===== ファイルアップロード処理 =====
  const handleFileUpload = async (event) => {
    const file = event.target.files[0];
    if (!file) return;

    if (connectionStatus !== "connected") {
      showToastNotification("先にエージェントに接続してください", "error");
      return;
    }

    // ファイルサイズチェック (10MB制限)
    const maxSize = 10 * 1024 * 1024;
    if (file.size > maxSize) {
      showToastNotification("ファイルサイズは10MB以下にしてください", "error");
      event.target.value = '';
      return;
    }

    setUploadStatus("アップロード中...");
    setIsLoading(true);
    setLoadingMessage(`${file.name}をアップロード中...`);

    const reader = new FileReader();
    reader.onload = (e) => {
      const base64Data = e.target.result.split(',')[1];
      const mimeType = file.type;

      console.log(`Uploading file: ${file.name}, type: ${mimeType}`);

      if (mimeType.startsWith('image/')) {
        voicecallApi.sendImageMessage(base64Data, mimeType);
        setUploadStatus(`画像「${file.name}」を送信しました`);
        setTranscriptions(prev => [...prev, {
          id: generateUniqueId(),
          text: `[画像送信] ${file.name}`,
          timestamp: new Date(),
          type: 'input',
          mediaType: 'image',
          mediaData: e.target.result // data:image/jpeg;base64,...
        }]);
        showToastNotification("画像を送信しました", "success");
      } else if (mimeType.startsWith('video/')) {
        voicecallApi.sendVideoMessage(base64Data, mimeType);
        setUploadStatus(`動画「${file.name}」を送信しました`);
        setTranscriptions(prev => [...prev, {
          id: generateUniqueId(),
          text: `[動画送信] ${file.name}`,
          timestamp: new Date(),
          type: 'input',
          mediaType: 'video',
          mediaData: e.target.result // data:video/mp4;base64,...
        }]);
        showToastNotification("動画を送信しました", "success");
      } else {
        setUploadStatus("対応していないファイル形式です");
        showToastNotification("対応していないファイル形式です", "error");
      }

      setTimeout(() => setUploadStatus(""), 3000);
      setIsLoading(false);
      setLoadingMessage("");
    };

    reader.onerror = () => {
      showToastNotification("ファイルの読み込みに失敗しました", "error");
      setIsLoading(false);
      setLoadingMessage("");
    };

    reader.readAsDataURL(file);
    event.target.value = '';
  };

  // ===== UIコンポーネント生成 =====

  // 接続ボタンの状態別表示
  const renderConnectionButton = () => {
    if (buttonDisabled) {
      return (
        <button className="w-full bg-gradient-to-r from-gray-400 to-gray-500 text-white font-bold py-4 px-8 rounded-2xl shadow-lg transition-all duration-300 text-lg cursor-not-allowed">
          {(connectionStatus == "connected") ? "接続を切断中..." : "接続中..."}
        </button>
      );
    } else if (connectionStatus == "connected") {
      return (
        <button
          className="w-full bg-gradient-to-r from-red-500 to-pink-600 hover:from-red-600 hover:to-pink-700 text-white font-bold py-4 px-8 rounded-2xl shadow-xl hover:shadow-2xl transition-all duration-300 transform hover:scale-105 hover:-translate-y-1 text-lg"
          onClick={disconnectFromBackend}
        >
          🔌 サポート終了
        </button>
      );
    } else {
      return (
        <button
          className="w-full bg-gradient-to-r from-purple-600 to-blue-500 hover:from-purple-700 hover:to-blue-600 text-white font-bold py-4 px-8 rounded-2xl shadow-xl hover:shadow-2xl transition-all duration-300 transform hover:scale-105 hover:-translate-y-1 text-lg relative overflow-hidden group"
          onClick={connectToBackend}
        >
          <span className="relative z-10">📞 サポートに連絡する</span>
          <div className="absolute inset-0 bg-gradient-to-r from-purple-400 to-blue-400 opacity-0 group-hover:opacity-20 transition-opacity duration-300"></div>
        </button>
      );
    }
  };

  // マイクボタンの状態別表示
  const renderMicrophoneButton = () => {
    if (connectionStatus !== "connected") return null;

    if (micStatus == "on") {
      return (
        <button
          className="w-full bg-gradient-to-r from-red-500 to-red-600 hover:from-red-600 hover:to-red-700 text-white font-bold py-4 px-8 rounded-2xl shadow-xl hover:shadow-2xl transition-all duration-300 transform hover:scale-105 flex items-center justify-center space-x-3 text-lg"
          onClick={() => setMicStatus("off")}
        >
          <span className="text-2xl animate-pulse">🔇</span>
          <span>マイクをミュート</span>
        </button>
      );
    } else {
      return (
        <button
          className="w-full bg-gradient-to-r from-green-500 to-emerald-600 hover:from-green-600 hover:to-emerald-700 text-white font-bold py-4 px-8 rounded-2xl shadow-xl hover:shadow-2xl transition-all duration-300 transform hover:scale-105 flex items-center justify-center space-x-3 text-lg"
          onClick={() => setMicStatus("on")}
        >
          <span className="text-2xl">🔊</span>
          <span>マイクをオン</span>
        </button>
      );
    }
  };

  // 接続状態インジケーター
  const renderStatusIndicator = () => (
    <div className="flex items-center justify-center space-x-4 mb-6 p-5 bg-gradient-to-r from-white to-slate-50 rounded-2xl shadow-lg border border-slate-200/60">
      <div className="relative">
        <div className={`w-5 h-5 rounded-full ${connectionStatus === "connected" ? "bg-green-500" : "bg-gray-400"}`}></div>
        {connectionStatus === "connected" && (
          <>
            <div className="absolute inset-0 w-5 h-5 rounded-full bg-green-400 animate-ping opacity-75"></div>
            <div className="absolute inset-0 w-5 h-5 rounded-full bg-green-300 animate-pulse"></div>
          </>
        )}
      </div>
      <span className="text-lg font-semibold text-gray-800">
        {connectionStatus === "connected" ? "📞 Sarahと通話中" : "📞 未接続"}
      </span>
      {connectionStatus === "connected" && (
        <div className="flex items-center space-x-2 ml-4 px-3 py-1 bg-white rounded-full shadow-sm">
          <div className={`w-3 h-3 rounded-full ${micStatus === "on" ? "bg-green-500 animate-pulse" : "bg-red-500"}`}></div>
          <span className="text-sm font-medium text-gray-700">
            {micStatus === "on" ? "🎤 マイクON" : "🔇 Muted"}
          </span>
        </div>
      )}
    </div>
  );

  // トランスクリプション表示コンポーネント
  const renderTranscriptions = () => {
    if (transcriptions.length === 0) {
      return (
        <div className="text-center text-gray-400 text-sm py-12">
          <div className="text-5xl mb-3 opacity-50">💬</div>
          <p className="text-lg">会話履歴がここに表示されます</p>
        </div>
      );
    }

    return (
      <div className="space-y-4 max-h-[500px] overflow-y-auto pr-2">
        {transcriptions.map((transcription, index) => {
          const isUser = transcription.type === 'input';
          const isSystem = transcription.type === 'system';

          return (
            <div
              key={transcription.id}
              className={`flex ${isUser ? 'justify-end' : 'justify-start'} animate-fade-in-up`}
            >
              <div className={`max-w-[80%] ${isUser
                ? 'bg-gradient-to-br from-purple-500 to-blue-500 text-white'
                : isSystem
                  ? 'bg-gradient-to-r from-green-50 to-emerald-50 border-2 border-green-200 text-green-900'
                  : 'bg-white text-gray-800 shadow-md'
                } rounded-2xl p-4 transform transition-all duration-200 hover:scale-[1.02]`}
              >
                <div className="flex justify-between items-start mb-2">
                  <span className={`text-xs font-semibold px-3 py-1 rounded-full ${isUser
                    ? 'bg-white/20 text-white'
                    : isSystem
                      ? 'bg-green-200 text-green-900'
                      : 'bg-blue-100 text-blue-700'
                    }`}>
                    {isUser ? '👤 User' : isSystem ? '🎫 System' : '🤖 Sarah'}
                  </span>
                  <span className={`text-xs ml-2 ${isUser ? 'text-white/80' : 'text-gray-500'
                    }`}>
                    {transcription.timestamp.toLocaleTimeString()}
                  </span>
                </div>
                <div className={`text-sm leading-relaxed prose prose-sm max-w-none ${isUser ? 'prose-invert' : ''
                  }`}>
                  <ReactMarkdown>{transcription.text}</ReactMarkdown>

                  {/* メディアプレビュー */}
                  {transcription.mediaData && (
                    <div className="mt-3">
                      {transcription.mediaType === 'image' ? (
                        <img
                          src={transcription.mediaData}
                          alt="uploaded"
                          className="max-w-xs rounded-lg shadow-md cursor-pointer hover:shadow-xl transition-shadow duration-200 border-2 border-white/20"
                          onClick={() => setZoomImage(transcription.mediaData)}
                        />
                      ) : transcription.mediaType === 'video' ? (
                        <video
                          src={transcription.mediaData}
                          controls
                          className="max-w-xs rounded-lg shadow-md border-2 border-white/20"
                        />
                      ) : null}
                    </div>
                  )}
                </div>
              </div>
            </div>
          );
        })}
        {/* 自動スクロール用の要素 */}
        <div ref={transcriptionsEndRef} />
      </div>
    );
  };

  // ===== メインレンダリング =====
  return (
    <div className="min-h-screen bg-slate-100 p-6 font-sans">
      {/* Toast Notification */}
      <ToastNotification
        message={toastMessage}
        type={toastType}
        isVisible={showToast}
        onClose={() => setShowToast(false)}
      />

      {/* Loading Indicator */}
      <LoadingIndicator
        message={loadingMessage}
        isVisible={isLoading}
      />

      {/* Image Zoom Modal */}
      <ImageZoomModal
        imageUrl={zoomImage}
        onClose={() => setZoomImage(null)}
      />

      {/* Ticket Modal */}
      <TicketModal
        isOpen={isModalOpen}
        onClose={() => setIsModalOpen(false)}
        ticketData={ticketData}
      />

      {/* ヘッダーセクション */}
      <div className="text-center mb-8 bg-gradient-to-br from-white via-blue-50 to-purple-50 p-8 rounded-3xl shadow-xl border border-white/60">
        <div className="flex items-center justify-center space-x-4 mb-3">
          <div className="text-5xl">🛠️</div>
          <h1 className="text-4xl font-bold bg-gradient-to-r from-purple-600 to-blue-600 bg-clip-text text-transparent">
            テクニカルサポート AIエージェント
          </h1>
        </div>
        <p className="text-slate-700 mb-5 text-lg">
          テクニカルサポート担当のSarahが、トラブルや操作方法についてサポートします。
        </p>

        {/* 使い方ガイド */}
        <div className="bg-blue-50 rounded-xl p-4 text-left max-w-3xl mx-auto border border-blue-100">
          <h3 className="text-sm font-bold text-blue-800 mb-2 flex items-center">
            <span className="mr-2">📖</span> デモの試し方
          </h3>
          <ul className="text-xs text-blue-900 space-y-1 list-disc list-inside">
            <li><strong>接続:</strong> 「サポートに連絡する」ボタンを押してSarahと会話を開始します。</li>
            <li><strong>質問:</strong> 「VPNの接続方法を教えて」と聞いてみてください。例：エラーコード 1001</li>
            <li><strong>画像/動画:</strong> エラー画面のスクショなどをアップロードして「このエラーは何？」と聞いてみてください。</li>
            <li><strong>チケット:</strong> 「解決しないのでチケットを切って」と頼むと、サポートチケットが作成されます。</li>
          </ul>
        </div>
      </div>

      {/* メインコンテンツ - 2カラムレイアウト */}
      <div className="max-w-6xl mx-auto grid grid-cols-1 lg:grid-cols-2 gap-8">

        {/* 左側: コントロールパネル */}
        <div className="space-y-6">

          {/* 通話コントロール */}
          <div className="bg-white rounded-2xl shadow-lg p-8 border border-slate-200">
            <h2 className="text-xl font-bold text-slate-800 mb-6 flex items-center">
              <span className="mr-2">🎧</span> 通話コントロール
            </h2>

            {renderStatusIndicator()}

            <div className="space-y-4">
              {renderConnectionButton()}
              {connectionStatus === "connected" && renderMicrophoneButton()}
            </div>

            {connectionStatus === "connected" && (
              <div className="mt-6 p-4 bg-blue-50 rounded-lg border border-blue-100">
                <h3 className="text-sm font-semibold text-blue-800 mb-2">💡 ヒント</h3>
                <p className="text-xs text-slate-700">
                  「VPNの接続方法を教えて」や「ゲストWi-Fiのパスワードは？」と聞いてみてください。
                </p>
              </div>
            )}
          </div>

          {/* メディアアップロード */}
          <div className="bg-white rounded-2xl shadow-lg p-8 border border-slate-200">
            <h2 className="text-xl font-bold text-slate-800 mb-4 flex items-center">
              <span className="mr-2">📤</span> 資料の共有
            </h2>
            <p className="text-sm text-slate-600 mb-4">
              エラー画面のスクリーンショットや、操作手順の動画をSarahに共有できます。
            </p>

            <div className="border-2 border-dashed border-slate-300 rounded-xl p-8 text-center hover:bg-slate-50 transition-colors relative">
              <input
                type="file"
                accept="image/*,video/*"
                onClick={(e) => {
                  if (connectionStatus !== "connected") {
                    e.preventDefault();
                    showToastNotification("先にエージェントに接続してください", "error");
                  }
                }}
                onChange={handleFileUpload}
                className="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
              />
              <div className="text-4xl mb-2">📁</div>
              <p className="text-slate-600 font-medium">
                クリックしてファイルを選択
              </p>
              <p className="text-xs text-slate-400 mt-1">
                画像 (JPG, PNG) または 動画 (MP4)
              </p>
            </div>

            {uploadStatus && (
              <div className="mt-4 p-3 bg-green-50 text-green-700 text-sm rounded-lg text-center animate-pulse">
                {uploadStatus}
              </div>
            )}
          </div>

        </div>

        {/* 右側: 会話ログ */}
        <div className="bg-white rounded-2xl shadow-lg p-6 border border-slate-200 h-[700px] flex flex-col">
          <div className="flex justify-between items-center border-b pb-4 mb-4">
            <h2 className="text-xl font-bold text-slate-800 flex items-center">
              <span className="mr-2">📝</span> サポート履歴
            </h2>
            {transcriptions.length > 0 && (
              <button
                onClick={exportTranscriptions}
                className="bg-slate-600 hover:bg-slate-700 text-white text-sm font-medium py-2 px-4 rounded-lg shadow-md transition-colors flex items-center space-x-2"
              >
                <span>💾</span>
                <span>履歴をエクスポート</span>
              </button>
            )}
          </div>

          <div className="flex-1 overflow-hidden">
            {renderTranscriptions()}
          </div>
        </div>

      </div>

      {/* フッター */}
      <div className="text-center mt-12 text-slate-400 text-xs">
        <p>Powered by Google Cloud Gemini Live API</p>
      </div>
    </div>
  );
}

