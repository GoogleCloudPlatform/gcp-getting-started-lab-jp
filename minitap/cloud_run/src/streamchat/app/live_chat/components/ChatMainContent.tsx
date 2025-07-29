"use client";

import { collection, query, orderBy, limit } from "firebase/firestore";
import { useCollection } from "react-firebase-hooks/firestore";
import { firestore } from "../../libs/firebase/init";
import Image from "next/image";
import { useEffect, useRef } from "react";

const ChatMainContent = () => {
  const [snapshot, loading, error] = useCollection(
    query(
      collection(firestore, "messages"),
      orderBy("timestamp", "desc"),
      limit(100)
    ),
    {
      snapshotListenOptions: { includeMetadataChanges: true },
    }
  );
  const messagesEndRef = useRef<HTMLDivElement>(null);

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  };

  useEffect(() => {
    scrollToBottom();
  }, [snapshot]);

  return (
    <main className="bg-white overflow-auto">
      <div className="mt-8">
        {snapshot && (
          <div>
            {snapshot.docs.reverse().map((doc) => {
              return (
                <>
                  <div key={doc.id} className="flex mb-2 px-6">
                    <div className="flex-none h-6 w-6 mr-4 relative">
                      <Image
                        src={
                          doc.data().profilePicUrl
                            ? doc.data().profilePicUrl
                            : "/images/placeholder.jpg"
                        }
                        fill
                        className="rounded-full"
                        alt="Avatar"
                      />
                    </div>
                    <span className="text-[13px] font-medium text-black text-opacity-50">
                      {doc.data().name}
                    </span>
                    <span className="ml-2 text-[13px] text-black">
                      {doc.data().text}
                    </span>
                  </div>
                </>
              );
            })}
          </div>
        )}
        <div ref={messagesEndRef} />
      </div>
    </main>
  );
};

export default ChatMainContent;
