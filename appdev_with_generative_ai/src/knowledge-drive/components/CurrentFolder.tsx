"use client";

import { useDocument } from "react-firebase-hooks/firestore";
import { usePathname } from "next/navigation";
import { getFirestore, doc } from "firebase/firestore";

import firebaseClientApp from "@/lib/firebase/client";
import { getFolderId } from "@/lib/utils";
import { User } from "firebase/auth";

const firestore = getFirestore(firebaseClientApp);

type CurrentFolderProps = {
  user: User;
};

const CurrentFolder = ({ user }: CurrentFolderProps) => {
  const pathname = usePathname();

  const [document, loading, error] = useDocument(
    doc(firestore, "users", user.uid, "items", getFolderId(pathname)),
    {
      snapshotListenOptions: { includeMetadataChanges: true },
    }
  );
  if (loading) return <></>;
  if (document === undefined || !document.data()) return <></>;

  return <span>{document.data()?.name}</span>;
};

export default CurrentFolder;
