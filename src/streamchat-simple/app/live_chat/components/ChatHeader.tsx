"use client";

import { useSignOut } from "react-firebase-hooks/auth";
import firebaseClientApp from "../../libs/firebase/client";
import { getAuth } from "firebase/auth";
import { PiSignOut } from "react-icons/pi";
import ThemeChanger from "./ThemeChanger";
import { Dispatch, SetStateAction } from "react";

const auth = getAuth(firebaseClientApp);

type ChatHeaderProps = {
  allMessages: boolean;
  setAllMessages: Dispatch<SetStateAction<boolean>>;
};

const ChatHeader = ({ allMessages, setAllMessages }: ChatHeaderProps) => {
  const [signOut] = useSignOut(auth);
  const handleClick = async () => {
    await signOut();
  };

  return (
    <header className="h-[48px] p-2 flex-none bg-white dark:bg-black border-solid border-b border-gray-300 dark:border-gray-700 flex items-center">
      <span
        onClick={() => {
          setAllMessages(!allMessages);
        }}
        className="text-md text-black dark:text-gray-200 px-4 transition bg-white dark:bg-black hover:bg-slate-200 hover:dark:bg-gray-800 cursor-pointer"
      >
        {allMessages ? "チャット" : "トップチャット"}
      </span>
      <div className="flex-auto" />
      <ThemeChanger />
      <span
        className="bg-white dark:bg-black px-2 py-1 flex gap-1 text-black dark:text-white hover:bg-slate-200 hover:dark:bg-gray-800 transition ml-2 mr-4 cursor-pointer items-center"
        onClick={handleClick}
      >
        <PiSignOut size={24} />
        サインアウト
      </span>
    </header>
  );
};

export default ChatHeader;
