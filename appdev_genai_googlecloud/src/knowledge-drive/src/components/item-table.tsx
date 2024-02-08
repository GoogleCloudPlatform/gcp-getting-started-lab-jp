import { headers } from "next/headers";
import { notFound } from "next/navigation";
import {
  getItemsByParentAndOwner,
  getOwner,
  isFolderExist,
} from "@/lib/actions";
import EmptyList from "@/components/empty-list";
import Item from "@/components/item";
import ItemHeader from "@/components/item-header";
import Refresh from "@/components/refresh";

type ItemTableProps = {
  parent: string;
};

const ItemTable = async ({ parent }: ItemTableProps) => {
  const headersList = headers();
  const owner = getOwner(headersList);

  const folderExist = await isFolderExist(parent, owner);
  if (!folderExist) {
    return notFound();
  }

  const items = await getItemsByParentAndOwner(parent, owner);

  if (items.length === 0)
    return (
      <EmptyList>
        <h1 className="mt-4 text-center text-xl">
          新規ボタンからフォルダの作成、
          <br />
          またはファイルをアップロードしてください
        </h1>
      </EmptyList>
    );

  return (
    <div className="flex flex-1 flex-col overflow-hidden pl-5 pr-3">
      <ItemHeader />
      <div className="flex-1 overflow-y-auto">
        {items.map((item) => (
          <Item key={item.id} item={item} />
        ))}
      </div>
      <Refresh intervalSecond={10} />
    </div>
  );
};

export default ItemTable;
