import { TItem } from "@/lib/types";
import { printFilesize } from "@/lib/utils";
import Link from "next/link";
import { BsThreeDotsVertical } from "react-icons/bs";
import { MdFolder } from "react-icons/md";
import { FaFile } from "react-icons/fa6";
import { HoverCard, HoverCardContent, HoverCardTrigger } from "./ui/hover-card";
import Image from "next/image";

type ItemProps = {
  item: TItem;
};

const Item = ({ item }: ItemProps) => {
  return (
    <Link
      href={item.isFolder ? `/folders/${item.id}` : `/items/${item.id}`}
      target={!item.isFolder ? "_blank" : ""}
    >
      <div className="flex h-12 items-center gap-x-2 border-b border-gray-300 hover:cursor-pointer hover:bg-slate-100">
        <div className="relative">
          {item.isFolder ? (
            <MdFolder
              size={24}
              color={"#444746"}
              className="ml-4 mr-2 min-w-6"
            />
          ) : (
            <>
              <FaFile
                size={24}
                color={item.embedded ? "#0000FF" : "#444746"}
                className="ml-4 mr-2 min-w-6"
              />
              {item.description && (
                <div className="absolute -top-1 right-0.5 h-4 w-4">
                  <Image
                    src="/images/check.png"
                    alt="check"
                    fill
                    sizes="10vw"
                  />
                </div>
              )}
            </>
          )}
        </div>
        {item.description ? (
          <HoverCard>
            <HoverCardTrigger asChild>
              <p className="mr-auto min-w-40 truncate text-sm">{item.name}</p>
            </HoverCardTrigger>
            <HoverCardContent align="start" className="w-[480px] bg-[#ebdbff]">
              <p>{item.description}</p>
            </HoverCardContent>
          </HoverCard>
        ) : (
          <p className="mr-auto min-w-40 truncate text-sm">{item.name}</p>
        )}
        <p className="w-32 min-w-32 truncate text-sm">{item.owner}</p>
        <p className="w-28 min-w-28 truncate text-sm">{item.createdAt}</p>
        <p className="w-24 min-w-32 truncate text-sm">
          {printFilesize(item.size)}
        </p>
        <BsThreeDotsVertical />
      </div>
    </Link>
  );
};

export default Item;
