import React from "react";
import ItemSelectorButton from "@/components/item-selector-button";
import type { ItemSelector } from "@/lib/types";

const itemSelectors: ItemSelector[] = [
  { text: "種類" },
  { text: "ユーザー" },
  { text: "最終更新" },
];

const ItemSelector = () => {
  return (
    <div className="ml-5 flex h-12 min-h-12 items-center gap-x-2">
      {itemSelectors.map((itemSelector) => {
        return (
          <ItemSelectorButton
            key={itemSelector.text}
            text={itemSelector.text}
          />
        );
      })}
    </div>
  );
};

export default ItemSelector;
