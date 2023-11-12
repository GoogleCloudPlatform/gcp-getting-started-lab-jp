import { User } from "firebase/auth";
import CurrentFolder from "./CurrentFolder";
import { BiGridAlt } from "react-icons/bi";
import { AiOutlineExclamationCircle } from "react-icons/ai";
import { MdArrowDropDown } from "react-icons/md";
import { usePathname } from "next/navigation";
import { isSearchPage } from "@/lib/utils";

type MainHeaderProps = {
  user: User;
};

const MainHeader = ({ user }: MainHeaderProps) => {
  const pathname = usePathname();

  return (
    <div className="w-full bg-white rounded-tl-2xl overflow-hidden min-h-[60px] pr-3">
      <div className="overflow-y-visible overflow-x-hidden relative flex flex-col w-full h-full">
        <div className="flex-none">
          <div className="flex w-full h-full">
            <div className="flex grow items-center overflow-hidden static">
              <div className="pt-[14px] pb-[6px] flex h-full w-full items-center overflow-hidden static">
                <div className="my-[2px] ml-1 py-1 pl-3 pr-4 text-[#3c4043] cursor-pointer max-w-full rounded-full text-left relative hover:bg-slate-100">
                  <div className="w-full truncate pl-[5px] align-top text-2xl">
                    {isSearchPage(pathname) ? (
                      "検索結果"
                    ) : (
                      <CurrentFolder user={user} />
                    )}
                  </div>
                </div>
              </div>
            </div>
            <div className="static items-start flex flex-none overflow-hidden justify-end">
              <div className="items-start pt-[14px] pb-[6px] static ml-[15px] mr-[11px] flex justify-end">
                <div className="my-[2px] mx-1 rounded-full overflow-visible relative flex align-center h-10 w-10 transition justify-center items-center">
                  <BiGridAlt size={20} />
                </div>
                <div className="my-[2px] mx-1 rounded-full overflow-visible relative flex align-center h-10 w-10 transition justify-center items-center">
                  <AiOutlineExclamationCircle size={20} />
                </div>
              </div>
            </div>
          </div>
        </div>
        <div className="min-h-[48px] relative flex-auto overflow-hidden">
          <div className="flex items-center pl-4">
            <div className="flex py-1 h-10 w-full visible">
              <div className="iterms-center flex flex-auto min-w-[24px] h-10 w-full visible ">
                <div className="max-w-full max-h-full visible">
                  <div className="flex max-w-full max-h-full items-center visible">
                    <div className="overflow-hidden relative visible">
                      <div className="flex w-full overflow-hidden h-full gap-x-1">
                        <div className="my-1 ml-1 h-8 flex rounded-md border border-[#80868b] leading-4 relative max-w-full text-[14px]">
                          <span className="flex items-center leading-4 px-2">
                            <span className="pl-2 pr-2">種類</span>
                            <MdArrowDropDown size={20} />
                          </span>
                        </div>
                        <div className="my-1 ml-1 h-8 flex rounded-md border border-[#80868b] leading-4 relative max-w-full text-[14px]">
                          <span className="flex items-center leading-4 px-2">
                            <span className="pl-2 pr-2">ユーザー</span>
                            <MdArrowDropDown size={20} />
                          </span>
                        </div>
                        <div className="my-1 ml-1 h-8 flex rounded-md border border-[#80868b] leading-4 relative max-w-full text-[14px]">
                          <span className="flex items-center leading-4 px-2">
                            <span className="pl-2 pr-2">最終更新</span>
                            <MdArrowDropDown size={20} />
                          </span>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default MainHeader;
