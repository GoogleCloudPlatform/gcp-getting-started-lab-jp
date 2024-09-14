"use client";

import { AiOutlinePlus } from "react-icons/ai";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import FileUploadButton from "@/components/file-upload-button";
import NewFolderButton from "@/components/new-folder-button";
import { useState } from "react";

const NewItemButton = () => {
  const [dropdownMenuOpen, setDropdownMenuOpen] = useState(false);

  const closeDropdownMenu = () => {
    setDropdownMenuOpen(false);
  };

  return (
    <DropdownMenu open={dropdownMenuOpen} onOpenChange={setDropdownMenuOpen}>
      <DropdownMenuTrigger asChild>
        <div className="mb-4 ml-4 mt-2 flex h-14 w-[105px] cursor-pointer items-center gap-3 rounded-2xl bg-white py-[18px] pl-4 pr-5 text-lightblack drop-shadow-md transition hover:bg-[#edf2fc]">
          <AiOutlinePlus size={24} className="text-lightblack" />
          <p>新規</p>
        </div>
      </DropdownMenuTrigger>
      <DropdownMenuContent
        sideOffset={-40}
        className="h-22 ml-4 flex w-[240px] flex-col gap-2 text-sm"
      >
        <NewFolderButton closeDropdownMenu={closeDropdownMenu} />
        <hr />
        <FileUploadButton closeDropdownMenu={closeDropdownMenu} />
      </DropdownMenuContent>
    </DropdownMenu>
  );
};

export default NewItemButton;
