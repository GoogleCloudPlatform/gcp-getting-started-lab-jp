import { IoMdCheckmark } from "react-icons/io";
import { RiMenuLine } from "react-icons/ri";
import { PiSquaresFour } from "react-icons/pi";
import DetailsButton from "@/components/details-button";

type ContentHeaderProps = {
  children: React.ReactNode;
};

const ContentHeader = ({ children }: ContentHeaderProps) => {
  return (
    <div className="flex h-16 min-h-16 items-center pb-[6px] pt-[14px]">
      {children}
      <div className="ml-auto flex items-center pl-3">
        <div className="flex h-8 w-14 items-center justify-center rounded-l-full border border-r-0 border-lightblack bg-blueselected">
          <IoMdCheckmark size={16} />
          <RiMenuLine size={20} />
        </div>
        <div className="flex h-8 w-14 items-center justify-center rounded-r-full border border-lightblack">
          <PiSquaresFour size={20} />
        </div>
        <DetailsButton />
      </div>
    </div>
  );
};

export default ContentHeader;
