"use client";

import { Dialog, DialogContent } from "@/components/ui/dialog";
import SearchResult from "./SearchResult";
import { User } from "firebase/auth";

type SearchDialogProps = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  query: string;
  csrfToken: string;
  user: User;
};

const SearchDialog = ({
  open,
  onOpenChange,
  query,
  csrfToken,
  user,
}: SearchDialogProps) => {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="min-h-[500px] min-w-[600px] bg-[#ebdbff]">
        <SearchResult user={user} query={query} csrfToken={csrfToken} />
      </DialogContent>
    </Dialog>
  );
};

export default SearchDialog;
