import { User } from "firebase/auth";
import { getFirestore, doc } from "firebase/firestore";
import { useDocumentDataOnce } from "react-firebase-hooks/firestore";

import firebaseClientApp from "@/lib/firebase/client";

const firestore = getFirestore(firebaseClientApp);

type SourceFileProps = {
  user: User;
  fileId: string;
};
const SourceFile = ({ user, fileId }: SourceFileProps) => {
  const [value, loading, error] = useDocumentDataOnce(
    doc(firestore, "users", user.uid, "items", fileId)
  );

  if (loading) return "";

  if (error) {
    return <span className="text-red-500">エラーが発生しました</span>;
  }

  if (!value) {
    return <span className="text-red-500">エラーが発生しました</span>;
  }

  return <span>{value.name}</span>;
};

export default SourceFile;
