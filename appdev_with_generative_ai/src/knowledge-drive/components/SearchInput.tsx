"use client";

import { AiOutlineSearch } from "react-icons/ai";
import { Input } from "./ui/input";
import { IoMdOptions } from "react-icons/io";
import * as z from "zod";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { Form, FormControl, FormField, FormItem, FormMessage } from "./ui/form";
import SearchDialog from "./SearchDialog";
import { useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { User } from "firebase/auth";

const formSchema = z.object({
  query: z
    .string({ required_error: "検索条件を入力してください" })
    .min(3, {
      message: "3 文字以上、70 文字以下で入力してください",
    })
    .max(50, {
      message: "3 文字以上、70 文字以下で入力してください",
    }),
});

type SearchInputProps = {
  csrfToken: string;
  user: User;
};
const SearchInput = ({ csrfToken, user }: SearchInputProps) => {
  const [searchDialogOpen, setSearchDialogOpen] = useState(false);
  const [isLLMSearch, setIsLLMSearch] = useState(false);
  const router = useRouter();
  const searchParams = useSearchParams();
  const search = searchParams.get("q") || "";

  const form = useForm<z.infer<typeof formSchema>>({
    resolver: zodResolver(formSchema),
    defaultValues: {
      query: search,
    },
  });

  function onSubmit(values: z.infer<typeof formSchema>) {
    const query = form.getValues("query");
    if (!query) return;
    if (isLLMSearch) {
      setSearchDialogOpen(true);
      return;
    }
    router.replace(`/search?q=${query}`);
  }

  const toggleFormType = () => {
    setIsLLMSearch(!isLLMSearch);
  };

  return (
    <div className="grow">
      <div
        className={`grow flex rounded-full items-center border border-transparent h-12 min-w-[500px] max-w-[722px] ${
          isLLMSearch ? "bg-[#ebdbff]" : "bg-[#edf2fc]"
        }`}
      >
        <div
          className={`w-14 h-[46px] my-0 mx-[5px] p-0 rounded-full text-black ${
            isLLMSearch ? "bg-[#ebdbff]" : "bg-[#edf2fc]"
          }`}
        >
          <AiOutlineSearch size={40} className="p-2 m-[3px]" />
        </div>
        <Form {...form}>
          <form onSubmit={form.handleSubmit(onSubmit)}>
            <FormField
              control={form.control}
              name="query"
              render={({ field }) => (
                <FormItem>
                  <FormControl>
                    <Input
                      className={`border-none w-[600px] text-[16px] focus-visible:ring-0 focus-visible:ring-offset-0 ${
                        isLLMSearch ? "bg-[#ebdbff]" : "bg-[#edf2fc]"
                      }`}
                      placeholder={
                        isLLMSearch
                          ? "質問文を入力"
                          : "ファイル名/フォルダ名で検索"
                      }
                      maxLength={70}
                      {...field}
                    />
                  </FormControl>
                </FormItem>
              )}
            />
          </form>
        </Form>
        <div onClick={toggleFormType}>
          <IoMdOptions size={40} className="p-[8px] m-[3px] cursor-pointer" />
        </div>
      </div>
      <SearchDialog
        open={searchDialogOpen}
        onOpenChange={setSearchDialogOpen}
        query={form.getValues("query")}
        csrfToken={csrfToken}
        user={user}
      />
    </div>
  );
};

export default SearchInput;
