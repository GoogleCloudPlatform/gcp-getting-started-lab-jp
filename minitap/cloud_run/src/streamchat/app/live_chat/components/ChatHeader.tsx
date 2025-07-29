"use client";
import { signOut } from "next-auth/react";

const ChatHeader = () => {
  const handleClick = async () => {
    await signOut({ callbackUrl: "/" });
  };
  return (
    <header className="h-[48px] p-2 flex-none bg-white border-solid border-b border-gray-300 flex items-center">
      <span className="text-md text-black hover:bg-gray-200 transition px-4 cursor-pointer">
        トップチャット
      </span>
      <div className="flex-auto" />
      <button
        className="bg-sky-500 px-2 py-1 hover:bg-sky-700 transition shadow ml-2 mr-4 rounded-md text-white"
        onClick={handleClick}
      >
        Sign out
      </button>
    </header>
  );
};

export default ChatHeader;
