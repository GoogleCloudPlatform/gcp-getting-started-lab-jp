"use client";

import { useSignOut } from "react-firebase-hooks/auth";
import firebaseClientApp from "../../libs/firebase/client";
import { getAuth } from "firebase/auth";
import { PiSignOut } from "react-icons/pi";

const auth = getAuth(firebaseClientApp);

const ChatHeader = () => {
  const [signOut] = useSignOut(auth);
  const handleClick = async () => {
    await signOut();
  };

  return (
    <header className="h-[48px] p-2 flex-none bg-white border-solid border-b border-gray-300 flex items-center">
      <span className="text-md text-black px-4">トップチャット</span>
      <div className="flex-auto" />
      <span
        className="bg-white px-2 py-1 flex gap-1 text-black hover:bg-slate-200 transition ml-2 mr-4 cursor-pointer items-center"
        onClick={handleClick}
      >
        <PiSignOut size={24} />
        サインアウト
      </span>
    </header>
  );
};

export default ChatHeader;
