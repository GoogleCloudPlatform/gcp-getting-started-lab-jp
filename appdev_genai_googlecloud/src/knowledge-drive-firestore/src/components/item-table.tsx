import { headers } from "next/headers";
import { notFound } from "next/navigation";
import {
  getItemsByParentAndOwner,
  getOwner,
  getSourceIP,
  isFolderExist,
} from "@/lib/actions";
import EmptyList from "@/components/empty-list";
import Item from "@/components/item";
import ItemHeader from "@/components/item-header";
import Refresh from "@/components/refresh";
import { logWarn } from "@/lib/logging";

type ItemTableProps = {
  parent: string;
};

const ItemTable = async ({ parent }: ItemTableProps) => {
  const action = "showItemTable";
  const headersList = headers();
  const sourceIP = await getSourceIP(headersList);
  const owner = await getOwner(headersList);

  const folderExist = await isFolderExist(parent, owner);
  if (!folderExist) {
    logWarn({
      owner: owner,
      sourceIP: sourceIP,
      action: action,
      message: `${sourceIP}/${owner}/${action}/${parent}: Failed to find folder with id ${parent}`,
    });
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
