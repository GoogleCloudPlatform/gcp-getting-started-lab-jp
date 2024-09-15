import SkeletonItemHeader from "@/components/skeleton-item-header";
import SkeletonItem from "@/components/skeleton-item";

const SkeletonItemTable = () => {
  return (
    <div className="flex flex-1 flex-col overflow-hidden pl-5 pr-3">
      <SkeletonItemHeader />
      <div className="flex-1 overflow-y-auto">
        <SkeletonItem />
        <SkeletonItem />
        <SkeletonItem />
        <SkeletonItem />
      </div>
    </div>
  );
};

export default SkeletonItemTable;
