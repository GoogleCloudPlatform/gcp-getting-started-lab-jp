import BreadcrumbFolder from "@/components/breadcrumb-folder";
import { getParents } from "@/lib/actions";
import { MdKeyboardArrowRight } from "react-icons/md";

type BreadcrumbProps = {
  parent: string;
};

const Breadcrumb = async ({ parent: id }: BreadcrumbProps) => {
  const folders = await getParents(id);
  return (
    <div className="flex min-w-[536px] max-w-[860px] items-center">
      {folders.map((folder, index) => (
        <div key={folder.id} className="flex min-w-0 items-center truncate">
          {index !== 0 && (
            <MdKeyboardArrowRight
              size={24}
              className="h-6 w-6 flex-none whitespace-nowrap"
            />
          )}
          <BreadcrumbFolder folder={folder} />
        </div>
      ))}
    </div>
  );
};

export default Breadcrumb;
