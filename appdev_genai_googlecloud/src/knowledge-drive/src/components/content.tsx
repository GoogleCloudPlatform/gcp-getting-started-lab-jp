import ContentHeader from "@/components/content-header";
import ItemSelector from "@/components/item-selector";
import ItemTable from "@/components/item-table";
import Breadcrumb from "@/components/breadcrumb";
import { Suspense } from "react";
import SkeletonBreadcrumb from "./skeleton-breadcrumb";
import SkeletonItemTable from "./skeleton-item-table";
import { randomUUID } from "crypto";

type ContentProps = {
  parent: string;
};

const Content = ({ parent }: ContentProps) => {
  return (
    <div className="flex flex-1 flex-col overflow-hidden">
      <div className="flex flex-1 flex-col overflow-hidden rounded-l-2xl bg-white">
        <ContentHeader>
          <Suspense fallback={<SkeletonBreadcrumb />}>
            <Breadcrumb parent={parent} />
          </Suspense>
        </ContentHeader>
        <ItemSelector />
        <Suspense key={randomUUID()} fallback={<SkeletonItemTable />}>
          <ItemTable parent={parent} />
        </Suspense>
      </div>
      <div className="h-2" />
    </div>
  );
};

export default Content;
