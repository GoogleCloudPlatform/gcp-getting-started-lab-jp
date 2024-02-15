import { getOwner, searchItemsByQueryAndOwner } from "@/lib/actions";
import EmptyList from "@/components/empty-list";
import Item from "@/components/item";
import ItemHeader from "@/components/item-header";
import { headers } from "next/headers";

type SearchItemProps = {
  queryText: string;
};

const SearchItemTable = async ({ queryText }: SearchItemProps) => {
  const headersList = headers();
  const owner = getOwner(headersList);

  const items = await searchItemsByQueryAndOwner(queryText, owner);

  if (items.length === 0) {
    return (
      <EmptyList>
        <h1 className="mt-4 text-center text-xl">
          検索条件にヒットするファイル、
          <br />
          フォルダが見つかりませんでした
        </h1>
      </EmptyList>
    );
  }

  return (
    <div className="flex flex-1 flex-col overflow-hidden pl-5 pr-3">
      <ItemHeader />
      <div className="flex-1 overflow-y-auto">
        {items.map((item) => (
          <Item key={item.id} item={item} />
        ))}
      </div>
    </div>
  );
};

export default SearchItemTable;
