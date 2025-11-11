"use client";

import {
  collection,
  query,
  orderBy,
  limit,
  getFirestore,
} from "firebase/firestore";
import { useCollection } from "react-firebase-hooks/firestore";
import firebaseClientApp from "../../libs/firebase/client";
import { useEffect, useRef } from "react";
import AvatarIcon from "./AvatarIcon";

const firestore = getFirestore(firebaseClientApp);

const ChatAllMainContent = () => {
  const [snapshot] = useCollection(
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
    <main className="bg-white dark:bg-black overflow-auto">
      <div className="mt-8">
        {snapshot && (
          <div>
            {snapshot.docs.reverse().map((doc) => {
              return (
                <>
                  <div key={doc.id} className="flex mb-2 px-6">
                    <AvatarIcon
                      bgColor={"bg-" + doc.data().color}
                      animal={doc.data().animal}
                    />
                    <span className="text-[13px] ml-4 pt-[2px] font-medium text-black dark:text-white text-opacity-50">
                      {doc.data().name}
                    </span>
                    <span className="ml-2 text-[13px] pt-[2px] text-black dark:text-white">
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

export default ChatAllMainContent;
