import { MdKeyboardArrowRight } from "react-icons/md";
import SkeletonBreadcrumbFolder from "./skeleton-breadcrumb-folder";

const SkeletonBreadcrumb = () => {
  return (
    <div className="flex min-w-[536px] max-w-[860px] items-center">
      <div className="flex min-w-0 items-center truncate">
        <SkeletonBreadcrumbFolder />
        <MdKeyboardArrowRight
          size={24}
          className="h-6 w-6 flex-none whitespace-nowrap"
        />
        <SkeletonBreadcrumbFolder />
        <MdKeyboardArrowRight
          size={24}
          className="h-6 w-6 flex-none whitespace-nowrap"
        />
        <SkeletonBreadcrumbFolder />
      </div>
    </div>
  );
};

export default SkeletonBreadcrumb;
