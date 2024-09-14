import NewItemButton from "@/components/new-item-button";
import LinkItem from "@/components/link-item";
import {
  MdDriveFolderUpload,
  MdOutlinePeopleAlt,
  MdOutlineAccessTime,
  MdOutlineCloud,
} from "react-icons/md";
import { FaLaptop } from "react-icons/fa6";
import { IoMdStarOutline } from "react-icons/io";
import { RiSpam2Line } from "react-icons/ri";
import { FaRegTrashAlt } from "react-icons/fa";

const Sidebar = () => {
  return (
    <aside className="w-64 min-w-64 overflow-y-auto">
      <NewItemButton />
      <LinkItem
        icon={<MdDriveFolderUpload size={20} className="text-default" />}
        description="マイドライブ"
        url="/my-drive"
      />
      <LinkItem
        icon={<FaLaptop size={20} className="text-default" />}
        description="パソコン"
        url="/computers"
        marginBottom={true}
        disabled={true}
      />
      <LinkItem
        icon={<MdOutlinePeopleAlt size={20} className="text-default" />}
        description="共有アイテム"
        url="/shared-with-me"
        disabled={true}
      />
      <LinkItem
        icon={<MdOutlineAccessTime size={20} className="text-default" />}
        description="最近使用したアイテム"
        url="/recent"
        disabled={true}
      />
      <LinkItem
        icon={<IoMdStarOutline size={20} className="text-default" />}
        description="スター付き"
        url="/starred"
        marginBottom={true}
        disabled={true}
      />
      <LinkItem
        icon={<RiSpam2Line size={20} className="text-default" />}
        description="スパム"
        url="/spam"
        disabled={true}
      />
      <LinkItem
        icon={<FaRegTrashAlt size={20} className="text-default" />}
        description="ゴミ箱"
        url="/trash"
        disabled={true}
      />
      <LinkItem
        icon={<MdOutlineCloud size={20} className="text-default" />}
        description="保存容量"
        url="/quota"
        disabled={true}
      />
    </aside>
  );
};

export default Sidebar;
