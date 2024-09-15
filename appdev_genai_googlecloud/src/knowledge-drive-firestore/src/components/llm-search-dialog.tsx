"use client";

import { Dialog, DialogContent } from "@/components/ui/dialog";
import LLMSearchResult from "@/components/llm-search-result";

type LLMSearchDialogProps = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  question: string;
};

const LLMSearchDialog = ({
  open,
  onOpenChange,
  question,
}: LLMSearchDialogProps) => {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="min-h-[500px] min-w-[600px] bg-[#ebdbff]">
        <LLMSearchResult question={question} />
      </DialogContent>
    </Dialog>
  );
};

export default LLMSearchDialog;
