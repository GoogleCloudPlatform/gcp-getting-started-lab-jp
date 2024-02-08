import Logo from "@/components/logo";
import AppName from "@/components/app-name";
import SearchForm from "@/components/search-form";
import Avatar from "@/components/avatar";
import Link from "next/link";
import { Suspense } from "react";

const Header = () => {
  return (
    <header className="flex h-16 min-h-16 items-center bg-thick p-2">
      <Link
        href="/"
        className="ml-1 flex w-[244px] min-w-[244px] items-center gap-x-2"
      >
        <Logo />
        <AppName />
      </Link>
      <Suspense>
        <SearchForm />
      </Suspense>
      <Avatar />
    </header>
  );
};

export default Header;
