"use client";

import { MdSearch } from "react-icons/md";
import { BiSlider } from "react-icons/bi";
import { useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import LLMSearchDialog from "@/components/llm-search-dialog";

const SearchForm = () => {
  const router = useRouter();
  const searchParams = useSearchParams();

  const searchParam = searchParams.get("q") || "";

  const [searchText, setSearchText] = useState(searchParam);
  const [isLLMSearch, setIsLLMSearch] = useState(false);
  const [llmSearchDialogOpen, setLLMSearchDialogOpen] = useState(false);

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setSearchText(e.target.value);
  };

  const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    if (!searchText) return;
    e.preventDefault();
    if (isLLMSearch) {
      setLLMSearchDialogOpen(true);
      return;
    }
    router.replace(`/search?q=${searchText}`);
  };

  const toggleIsLLMSearch = () => {
    setIsLLMSearch(!isLLMSearch);
  };

  return (
    <>
      <form
        onSubmit={handleSubmit}
        className={`mr-6 flex h-12 min-w-[500px] max-w-[722px] grow items-center rounded-full px-4 transition focus-within:bg-white focus-within:shadow-sm ${isLLMSearch ? "bg-[#ebdbff]" : "bg-[#e9eef6]"}`}
      >
        <MdSearch className="mr-4 text-lightblack" size={24} />
        <input
          type="text"
          placeholder={isLLMSearch ? "質問文を入力" : "ドライブで検索"}
          className={`flex-1 text-lg text-lightblack placeholder-lightblack outline-none transition focus:bg-white ${isLLMSearch ? "bg-[#ebdbff]" : "bg-[#e9eef6]"}`}
          value={searchText}
          onChange={handleChange}
          autoComplete="off"
          minLength={3}
        />
        <BiSlider
          onClick={toggleIsLLMSearch}
          className="ml-4 text-lightblack hover:cursor-pointer"
          size={24}
        />
      </form>
      <LLMSearchDialog
        open={llmSearchDialogOpen}
        onOpenChange={setLLMSearchDialogOpen}
        question={searchText}
      />
    </>
  );
};

export default SearchForm;
