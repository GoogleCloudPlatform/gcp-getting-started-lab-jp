"use client";

import SingleItem from "./SingleItem";
import { QueryDocumentSnapshot, DocumentData } from "firebase/firestore";

type MainItemsProps = {
  docs: QueryDocumentSnapshot<DocumentData, DocumentData>[];
};

const MainItemsContent = ({ docs }: MainItemsProps) => {
  return (
    <>
      {docs.map((doc) => (
        <SingleItem
          key={doc.id}
          id={doc.id}
          name={doc.data().name}
          timestamp={doc.data().timestamp?.toDate()}
          isFolder={doc.data().isFolder}
          size={doc.data().size}
          url={doc.data().url}
          description={doc.data().description}
        />
      ))}
    </>
  );
};

export default MainItemsContent;
