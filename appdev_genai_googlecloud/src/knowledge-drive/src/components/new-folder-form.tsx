"use client";

import {
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { getParentFromPath } from "@/lib/utils";
import { createFolder } from "@/lib/actions";

type NewFolderFormProps = {
  closeDropdownMenu: () => void;
  closeDialog: () => void;
};

const NewFolderForm = ({
  closeDropdownMenu,
  closeDialog,
}: NewFolderFormProps) => {
  const pathname = usePathname();
  const router = useRouter();
  const [folderName, setFolderName] = useState("");

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setFolderName(e.target.value);
  };

  const handleClickCancel = () => {
    setFolderName("");
  };

  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    // ToDo: Add toasts and error handling
    await createFolder(folderName, getParentFromPath(pathname));
    closeDialog();
    closeDropdownMenu();
    setFolderName("");
    router.refresh();
  };

  return (
    <DialogContent className="w-[340px]">
      <form onSubmit={handleSubmit}>
        <DialogHeader>
          <DialogTitle className="text-2xl">新しいフォルダ</DialogTitle>
        </DialogHeader>
        <input
          name="folderName"
          type="text"
          placeholder="無題のフォルダ"
          className="mb-4 mt-5 flex h-[42px] w-full items-center rounded-md border border-black px-3 transition"
          value={folderName}
          onChange={handleChange}
          autoComplete="off"
        />
        <section className="flex items-center justify-end">
          <Button
            type="reset"
            variant="ghost"
            onClick={handleClickCancel}
            className="rounded-full text-sm text-[#0B57D0]"
          >
            キャンセル
          </Button>
          <Button
            type="submit"
            variant="ghost"
            disabled={!folderName}
            className="test-sm rounded-full text-[#0B57D0] disabled:text-gray-400"
          >
            作成
          </Button>
        </section>
      </form>
    </DialogContent>
  );
};

export default NewFolderForm;
