import { addDoc, collection, serverTimestamp } from "firebase/firestore";
import { firestore } from "./init";

export const saveMessage = async (
  username: string,
  text: string,
  profilePicUrl: string
) => {
  const message = {
    name: username,
    text: text,
    profilePicUrl: profilePicUrl,
    timestamp: serverTimestamp(),
  };

  await addDoc(collection(firestore, "messages"), message);
};
