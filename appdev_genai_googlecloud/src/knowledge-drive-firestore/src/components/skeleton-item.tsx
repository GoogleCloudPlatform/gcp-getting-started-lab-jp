import { BsThreeDotsVertical } from "react-icons/bs";
import { Skeleton } from "@/components/ui/skeleton";

const SkeletonItem = () => {
  return (
    <div className="flex h-12 items-center gap-x-2 border-b border-gray-300 hover:cursor-pointer hover:bg-slate-100">
      <Skeleton className="ml-4 mr-2 h-6 w-6 min-w-6 rounded-full" />
      <p className="mr-auto min-w-40 truncate text-sm">
        <Skeleton className="h-5 w-64" />
      </p>
      <p className="w-32 min-w-32 truncate text-sm">
        <Skeleton className="h-5 w-24" />
      </p>
      <p className="w-28 min-w-28 truncate text-sm">
        <Skeleton className="h-5 w-24" />
      </p>
      <p className="w-24 min-w-32 truncate text-sm">
        <Skeleton className="h-5 w-24" />
      </p>
      <BsThreeDotsVertical />
    </div>
  );
};

export default SkeletonItem;
