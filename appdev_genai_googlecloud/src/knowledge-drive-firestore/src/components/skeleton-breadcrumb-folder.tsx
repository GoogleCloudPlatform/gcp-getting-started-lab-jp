import { Skeleton } from "@/components/ui/skeleton";

const SkeletonBreadcrumbFolder = () => {
  return (
    <div className="my-[2px] ml-1 min-w-0 rounded-full py-1 pl-4 pr-3">
      <Skeleton className="h-8 w-32 min-w-0 leading-8" />
    </div>
  );
};

export default SkeletonBreadcrumbFolder;
