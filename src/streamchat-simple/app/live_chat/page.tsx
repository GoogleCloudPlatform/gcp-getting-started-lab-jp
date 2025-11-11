"use client";

import { useEffect, useState } from "react";
import ChatFooter from "./components/ChatFooter";
import ChatHeader from "./components/ChatHeader";
import ChatMainContent from "./components/ChatMainContent";
import { useAuthState } from "react-firebase-hooks/auth";

import { getAuth } from "firebase/auth";

import firebaseClientApp from "../libs/firebase/client";
import { useRouter } from "next/navigation";
import LoadingPage from "../components/LoadingPage";
import ChatAllMainContent from "./components/ChatAllMainContent";

const auth = getAuth(firebaseClientApp);

const LiveChat = () => {
  const [csrfToken, setCsrfToken] = useState("loading...");
  const [user, loading] = useAuthState(auth);
  const [allMessages, setAllMessages] = useState(false);

  const router = useRouter();

  useEffect(() => {
    const el = document.querySelector(
      'meta[name="x-csrf-token"]'
    ) as HTMLMetaElement | null;
    if (el) setCsrfToken(el.content);
    else setCsrfToken("missing");
  }, []);

  if (loading) {
    return <LoadingPage />;
  }

  if (!user) {
    return router.push("/");
  }

  return (
    <>
      <div className="flex flex-col h-screen">
        <ChatHeader allMessages={allMessages} setAllMessages={setAllMessages} />
        {allMessages ? <ChatAllMainContent /> : <ChatMainContent />}
        <ChatFooter csrfToken={csrfToken} user={user} />
      </div>
    </>
  );
};

export default LiveChat;
