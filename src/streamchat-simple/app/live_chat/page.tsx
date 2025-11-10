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

const auth = getAuth(firebaseClientApp);

const LiveChat = () => {
  const [csrfToken, setCsrfToken] = useState("loading...");
  const [user, loading] = useAuthState(auth);

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
        <ChatHeader />
        <ChatMainContent />
        <ChatFooter csrfToken={csrfToken} user={user} />
      </div>
    </>
  );
};

export default LiveChat;
