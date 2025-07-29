"use client";

import ChatFooter from "./components/ChatFooter";
import ChatMainContent from "./components/ChatMainContent";
import ChatHeader from "./components/ChatHeader";

const LiveChat = () => {
  return (
    <>
      <div className="flex flex-col h-screen">
        <ChatHeader />
        <ChatMainContent />
        <ChatFooter />
      </div>
    </>
  );
};

export default LiveChat;
