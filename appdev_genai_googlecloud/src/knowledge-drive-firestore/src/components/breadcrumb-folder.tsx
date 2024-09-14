import { MY_DRIVE_URL, ROOT_FOLDER_ID } from "@/lib/constants";
import Link from "next/link";

type BreadcrumbFolder = {
  id: string;
  name: string;
  // parent: string;
};

type BreadcrumbFolderProps = {
  folder: BreadcrumbFolder;
};

const BreadcrumbFolder = ({ folder }: BreadcrumbFolderProps) => {
  const getFolderLink = (id: string) => {
    if (id === ROOT_FOLDER_ID) return MY_DRIVE_URL;
    return `/folders/${id}`;
  };

  return (
    <Link href={getFolderLink(folder.id)} className="truncate">
      <div className="my-[2px] ml-1 min-w-0 rounded-full py-1 pl-4 pr-3 transition hover:bg-[#e4e5e9]">
        <p className="h-8 min-w-0 truncate text-[24px] leading-8 text-lightblack">
          {folder.name}
        </p>
      </div>
    </Link>
  );
};

export default BreadcrumbFolder;
