import { cn } from "@/lib/utils";
import { IoMdArrowDropdown } from "react-icons/io";

type ItemSelectorButtonProps = {
  text: string;
};

const ItemSelectorButton = ({ text }: ItemSelectorButtonProps) => {
  return (
    <div className="flex h-[30px] flex-none items-center gap-x-1 rounded-lg border border-lightblack pl-2 pr-3">
      <p className="pl-2 pr-1 text-lightblack">{text}</p>
      <IoMdArrowDropdown />
    </div>
  );
};

export default ItemSelectorButton;
