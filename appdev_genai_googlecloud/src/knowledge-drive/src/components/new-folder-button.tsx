"use client";

import { AiOutlineFolderAdd } from "react-icons/ai";
import { Dialog, DialogTrigger } from "@/components/ui/dialog";
import NewFolderForm from "@/components/new-folder-form";
import { useState } from "react";

type NewFolderButtonProps = {
  closeDropdownMenu: () => void;
};

const NewFolderButton = ({ closeDropdownMenu }: NewFolderButtonProps) => {
  const [dialogOpen, setDialogOpen] = useState(false);

  const closeDialog = () => {
    setDialogOpen(false);
  };

  return (
    <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
      <DialogTrigger>
        <div className="mt-2 flex h-8 items-center gap-3 px-2 hover:bg-slate-200">
          <AiOutlineFolderAdd size={24} />
          <p className="font-medium">新しいフォルダ</p>
        </div>
      </DialogTrigger>
      <NewFolderForm
        closeDropdownMenu={closeDropdownMenu}
        closeDialog={closeDialog}
      />
    </Dialog>
  );
};

export default NewFolderButton;
