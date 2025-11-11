import { Message } from "@/app/types/message";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import firebaseAdminApp from "./admin";

export const postMessage = async (message: Message) => {
  await getFirestore(firebaseAdminApp).collection("messages").doc().set({
    name: message.name,
    text: message.text,
    animal: message.animal,
    color: message.color,
    timestamp: FieldValue.serverTimestamp(),
  });
};
