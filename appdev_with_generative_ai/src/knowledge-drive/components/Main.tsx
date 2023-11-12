import { User } from "firebase/auth";
import MainHeader from "./MainHeader";
import RecommendedList from "./RecommendedList";
import MainItems from "./MainItems";
import { usePathname } from "next/navigation";
import { isSearchPage } from "@/lib/utils";
import SearchItems from "./SearchItems";

type MainProps = {
  user: User;
};

const Main = ({ user }: MainProps) => {
  const pathname = usePathname();

  return (
    <main className="grid-in-main flex flex-col">
      <MainHeader user={user} />
      <div className="grow w-full relative mb-4 overflow-hidden bg-white">
        <div className="h-full w-full flex static">
          <div className="flex-auto h-full w-full">
            <div className="flex h-full relative w-full flex-wrap overflow-y-scroll flex-col">
              <RecommendedList />
              {isSearchPage(pathname) ? (
                <SearchItems user={user} />
              ) : (
                <MainItems user={user} />
              )}
              {/* <MainItems user={user} /> */}
            </div>
          </div>
        </div>
      </div>
    </main>
  );
};

export default Main;
