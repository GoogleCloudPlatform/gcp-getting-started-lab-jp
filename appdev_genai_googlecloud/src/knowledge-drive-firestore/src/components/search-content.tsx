import ItemSelector from "@/components/item-selector";
import ContentHeader from "@/components/content-header";
import SearchContentText from "@/components/search-content-text";
import SearchItemTable from "@/components/search-item-table";
import { Suspense } from "react";
import SkeletonItemTable from "./skeleton-item-table";
import { randomUUID } from "crypto";

type SearchContentProps = {
  queryText: string;
};

const SearchContent = ({ queryText }: SearchContentProps) => {
  return (
    <div className="flex flex-1 flex-col overflow-hidden">
      <div className="flex flex-1 flex-col overflow-hidden rounded-l-2xl bg-white">
        <ContentHeader>
          <SearchContentText />
        </ContentHeader>
        <ItemSelector />
        <Suspense key={randomUUID()} fallback={<SkeletonItemTable />}>
          <SearchItemTable queryText={queryText} />
        </Suspense>
      </div>
      <div className="h-2" />
    </div>
  );
};

export default SearchContent;
