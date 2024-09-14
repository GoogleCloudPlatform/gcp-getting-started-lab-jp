import SearchContent from "@/components/search-content";
import Sidebar from "@/components/sidebar";
import { MY_DRIVE_URL } from "@/lib/constants";
import { redirect } from "next/navigation";
import Screen from "@/components/screen";

type SearchPageProps = {
  searchParams: { [key: string]: string | string[] };
};

export default async function SearchPage({ searchParams }: SearchPageProps) {
  const queryText = searchParams["q"];
  if (queryText === undefined) {
    redirect(MY_DRIVE_URL);
  }

  return (
    <Screen>
      <Sidebar />
      <SearchContent queryText={queryText as string} />
    </Screen>
  );
}
