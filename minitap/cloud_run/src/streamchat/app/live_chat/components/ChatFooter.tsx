"use client";

import axios from "axios";
import { useSession } from "next-auth/react";
import Image from "next/image";
import { useState } from "react";
import { SubmitHandler, useForm } from "react-hook-form";
import { AiOutlineSend } from "react-icons/ai";
import toast from "react-hot-toast";

type FormValues = {
  message: string;
};

const ChatFooter = () => {
  const { data: session, status } = useSession();
  const [isLoading, setIsLoading] = useState(false);

  const {
    register,
    handleSubmit,
    watch,
    reset,
    formState: { errors },
  } = useForm<FormValues>({
    defaultValues: {
      message: "",
    },
  });

  const onSubmit: SubmitHandler<FormValues> = async (data) => {
    setIsLoading(true);
    try {
      await axios.post("/api/messages", data);
      // await axios.post("/api/pubsub", data);
      reset();
    } catch (error) {
      toast.error("Failed to send message: " + error);
    } finally {
      setIsLoading(false);
    }
  };

  const messageLength = watch().message.length || 0;

  return (
    <footer className="h-[111px] flex-none mt-auto p-4 bg-white border-gray-300 border-t">
      <div className="ml-2 flex">
        <div className="flex-none w-6 h-6 relative">
          <Image
            src={
              session?.user?.image
                ? session.user.image
                : "/images/placeholder.jpg"
            }
            alt="avatar"
            fill
            className="rounded-full"
          />
        </div>
        <div className="flex-row px-4 w-full justify-start">
          <div className="text-[13px] text-black text-opacity-50">
            {session?.user?.name ? session.user.name : "unknown"}
          </div>
          <form className="w-full" onSubmit={handleSubmit(onSubmit)}>
            <input
              id="message"
              type="text"
              placeholder="メッセージを入力..."
              aria-label="Full name"
              {...register("message", { required: true })}
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
            <button onClick={handleSubmit(onSubmit)}>
              <AiOutlineSend className="p-2" size={40} color={"#ccc"} />
            </button>
          </div>
        </div>
      </div>
    </footer>
  );
};

export default ChatFooter;
