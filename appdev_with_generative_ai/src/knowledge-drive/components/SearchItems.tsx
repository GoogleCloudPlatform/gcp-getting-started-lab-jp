import { User } from "firebase/auth";
import MainItemsContent from "./MainItemsContent";
import MainItemsHeader from "./MainItemsHeader";
import { useSearchParams } from "next/navigation";
import { useCollection } from "react-firebase-hooks/firestore";
import {
  collection,
  getFirestore,
  orderBy,
  query,
  where,
} from "firebase/firestore";
import firebaseClientApp from "@/lib/firebase/client";
import { Skeleton } from "./ui/skeleton";
import Image from "next/image";

const firestore = getFirestore(firebaseClientApp);

type SearchItemsProps = {
  user: User;
};

const SearchItems = ({ user }: SearchItemsProps) => {
  const searchParams = useSearchParams();
  const search = searchParams.get("q");

  const [snapshot, loading, error] = useCollection(
    query(
      collection(firestore, "users", user.uid, "items"),
      where("name", "==", search),
      orderBy("timestamp", "desc")
    ),
    {
      snapshotListenOptions: { includeMetadataChanges: true },
    }
  );
  snapshot?.docs;

  if (error) {
    return <strong>Error: {JSON.stringify(error)}</strong>;
  }

  if (loading) {
    return (
      <div className="w-full pr-3 pl-5">
        <div className="flex flex-col gap-1 pt-4">
          <Skeleton className="h-6 w-full" />
          <Skeleton className="h-6 w-full" />
        </div>
        <div className="flex flex-col gap-1 pt-4">
          <Skeleton className="h-6 w-full" />
          <Skeleton className="h-6 w-full" />
        </div>
        <div className="flex flex-col gap-1 pt-4">
          <Skeleton className="h-6 w-full" />
          <Skeleton className="h-6 w-full" />
        </div>
        <div className="flex flex-col gap-1 pt-4">
          <Skeleton className="h-6 w-full" />
          <Skeleton className="h-6 w-full" />
        </div>
        <div className="flex flex-col gap-1 pt-4">
          <Skeleton className="h-6 w-full" />
          <Skeleton className="h-6 w-full" />
        </div>
        <div className="flex flex-col gap-1 pt-4">
          <Skeleton className="h-6 w-full" />
          <Skeleton className="h-6 w-full" />
        </div>
      </div>
    );
  }

  if (!snapshot) return <></>;

  if (snapshot.docs.length > 0) {
    return (
      <div className="flex flex-col flex-autozero w-full h-full">
        <MainItemsHeader />
        <MainItemsContent docs={snapshot.docs} />
      </div>
    );
  }

  return (
    <div className="flex w-full h-full justify-center items-center">
      <div className="h-[300px] w-full flex flex-col justify-center items-center">
        <div className="h-[200px] w-[200px] rounded-full bg-gray-100 flex items-center justify-center">
          <Image
            src="/images/notfound.png"
            width={200}
            height={200}
            alt="NotFound"
          />
        </div>
        <h1 className="text-xl mt-4">
          条件に一致するファイルやフォルダはありませんでした
        </h1>
      </div>
    </div>
  );
};

export default SearchItems;
