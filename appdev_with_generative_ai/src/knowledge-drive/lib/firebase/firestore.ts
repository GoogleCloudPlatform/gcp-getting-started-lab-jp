import firebaseClientApp from "./client";
import {
  getFirestore,
  addDoc,
  serverTimestamp,
  collection,
  setDoc,
  doc,
} from "firebase/firestore";

const firestore = getFirestore(firebaseClientApp);

type Folder = {
  name: string;
  parent: string;
  uid: string;
};

type File = {
  id: string;
  name: string;
  parent: string;
  uid: string;
  size: number;
  url: string;
};

export const createFolder = async ({ name, parent, uid }: Folder) => {
  await addDoc(collection(firestore, "users", uid, "items"), {
    name: name,
    parent: parent,
    isFolder: true,
    timestamp: serverTimestamp(),
    size: 0,
  });
};

export const createFile = async ({
  id,
  name,
  parent,
  uid,
  size,
  url,
}: File) => {
  await setDoc(doc(firestore, "users", uid, "items", id), {
    name: name,
    parent: parent,
    isFolder: false,
    timestamp: serverTimestamp(),
    size: size,
    url: url,
  });
};
