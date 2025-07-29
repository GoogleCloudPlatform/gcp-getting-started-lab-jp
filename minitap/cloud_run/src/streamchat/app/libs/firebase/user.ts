import { collection, query, where, getDocs, addDoc } from "firebase/firestore";
import { firestore } from "./init";

type User = {
  id: string;
  name: string;
  email: string;
  hashedPassword: string;
};

export const getUserByEmail = async (email: string): Promise<User | null> => {
  const usersRef = collection(firestore, "users");
  const q = query(usersRef, where("email", "==", email));

  const querySnapshot = await getDocs(q);
  if (querySnapshot.empty) return null;

  return querySnapshot.docs[0].data() as User;
};

export const addUser = async (
  name: string,
  email: string,
  hashedPassword: string
) => {
  const docRef = await addDoc(collection(firestore, "users"), {
    name: name,
    email: email,
    hashedPassword: hashedPassword,
  });
  return {
    id: docRef.id,
    name: name,
    email: email,
    hashedPassword: hashedPassword,
  };
};
