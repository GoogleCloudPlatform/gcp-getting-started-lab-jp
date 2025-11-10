"use client";

import {
  ChangeEvent,
  FormEventHandler,
  MouseEventHandler,
  useState,
} from "react";
import { AiOutlineSend } from "react-icons/ai";
import toast from "react-hot-toast";
import { User } from "firebase/auth";
import CurrentUserAvatar from "./CurrentUserAvatar";
import { postMessageApi } from "@/app/libs/api/message";

type Props = {
  csrfToken: string;
  user: User;
};

const ChatFooter = ({ csrfToken, user }: Props) => {
  const [isLoading, setIsLoading] = useState(false);
  const [message, setMessage] = useState("");

  const handleMessageChange = (e: ChangeEvent<HTMLInputElement>) => {
    setMessage(e.target.value);
  };

  const handleSubmit = (
    tokenVal: string
  ): FormEventHandler<HTMLFormElement> => {
    return async (event: React.FormEvent<HTMLFormElement>) => {
      event.preventDefault();
      await handlePostMessage(tokenVal);
    };
  };

  const handleClickButton = (
    tokenVal: string
  ): MouseEventHandler<HTMLButtonElement> => {
    return async () => {
      await handlePostMessage(tokenVal);
    };
  };

  const handlePostMessage = async (tokenVal: string) => {
    setIsLoading(true);
    const idToken = await user?.getIdToken();
    try {
      await postMessageApi(
        { message: message },
        idToken ? idToken : "",
        tokenVal
      );
      setMessage("");
    } catch (error) {
      toast.error("Failed to post message: " + error);
    } finally {
      setIsLoading(false);
    }
  };

  const messageLength = message.length || 0;

  return (
    <footer className="h-[111px] flex-none mt-auto p-4 bg-white border-gray-300 border-t">
      <div className="ml-2 flex">
        <CurrentUserAvatar uid={user.uid} />
        <div className="flex-row px-4 w-full justify-start">
          <div className="text-[13px] text-black text-opacity-50">
            {user.displayName}
          </div>
          <form className="w-full" onSubmit={handleSubmit(csrfToken)}>
            <input
              id="message"
              type="text"
              placeholder="メッセージを入力..."
              aria-label="Full name"
              disabled={isLoading}
              value={message}
              required
              onChange={handleMessageChange}
              className="appearance-none bg-transparent placeholder-black
                  placeholder-opacity-70 border-none w-full text-[13px] text-black leading-tight focus:outline-none"
            />
            <div className="h-[1px] w-full bg-black bg-opacity-50" />
          </form>
          <div className="flex items-center mt-1 gap-4">
            <div className="flex-auto" />
            <span className="text-black text-opacity-70 text-[12px]">
              {messageLength}/200
            </span>
            <button disabled={isLoading} onClick={handleClickButton(csrfToken)}>
              <AiOutlineSend className="p-2" size={40} color={"#ccc"} />
            </button>
          </div>
        </div>
      </div>
    </footer>
  );
};

export default ChatFooter;
