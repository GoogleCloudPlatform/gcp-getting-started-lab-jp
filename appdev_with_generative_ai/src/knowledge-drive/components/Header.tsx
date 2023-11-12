"use client";

import { useSignOut } from "react-firebase-hooks/auth";
import firebaseClientApp from "@/lib/firebase/client";
import { User, getAuth } from "firebase/auth";
import { PiSignOut } from "react-icons/pi";
import Image from "next/image";
import { Avatar, AvatarImage, AvatarFallback } from "@/components/ui/avatar";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import Link from "next/link";
import SearchInput from "./SearchInput";

const auth = getAuth(firebaseClientApp);

type HeaderProps = {
  user: User;
  csrfToken: string;
};

const Header = ({ user, csrfToken }: HeaderProps) => {
  const [signOut] = useSignOut(auth);
  const handleClick = async () => {
    await signOut();
  };

  return (
    <div className="grid-in-header">
      <header className="p-2 flex w-full items-center">
        <div className="flex p-2 h-12">
          <div className="flex pl-3 items-center w-[230px] ">
            <Link href="/drive" className="flex items-center">
              <div className="pr-1 h-[52px] w-[52px] relative">
                <Image src="/images/logo.png" fill alt="Logo" />
              </div>
              <span className="text-[22px] text-black pl-1 transition cursor-pointer">
                ドライブ
              </span>
            </Link>
          </div>
        </div>
        <SearchInput csrfToken={csrfToken} user={user} />
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Avatar className="m-1 cursor-pointer">
              <AvatarImage src="/images/placeholder.png" alt="avatar" />
              <AvatarFallback>CN</AvatarFallback>
            </Avatar>
          </DropdownMenuTrigger>
          <DropdownMenuContent className="w-[400px] h-[340px] bg-[#edf2fc] mt-1 mr-4 flex flex-col items-center transition rounded-3xl">
            <div className="py-4">{user.email}</div>
            <Avatar className="m-2 h-[80px] w-[80px]">
              <AvatarImage
                className="w-full h-full"
                src="/images/placeholder.png"
                alt="avatar"
              />
              <AvatarFallback>CN</AvatarFallback>
            </Avatar>
            <div className="py-2 text-2xl">{user.displayName} 様</div>

            <span
              className="px-2 py-1 flex gap-2 text-black bg-white hover:bg-slate-200 transition ml-2 mr-4 mt-10 cursor-pointer items-center w-44 h-16 justify-center rounded-full"
              onClick={handleClick}
            >
              <PiSignOut size={24} />
              <span>ログアウト</span>
            </span>
          </DropdownMenuContent>
        </DropdownMenu>
      </header>
    </div>
  );
};

export default Header;
