import { BsThreeDotsVertical } from "react-icons/bs";
import { Skeleton } from "@/components/ui/skeleton";

const SkeletonItemHeader = () => {
  return (
    <div className="flex h-12 items-center gap-x-2 border-b border-gray-300 pt-2">
      <p className="mr-auto min-w-[216px]">
        <Skeleton className="h-5 w-12" />
      </p>
      <p className="w-32 min-w-32">
        <Skeleton className="h-5 w-16" />
      </p>
      <p className="w-28 min-w-28">
        <Skeleton className="h-5 w-16" />
      </p>
      <p className="w-24 min-w-32">
        <Skeleton className="h-5 w-24" />
      </p>
      <BsThreeDotsVertical />
    </div>
  );
};

export default SkeletonItemHeader;
