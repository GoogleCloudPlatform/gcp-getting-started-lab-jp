import Content from "@/components/content";
import Screen from "@/components/screen";
import Sidebar from "@/components/sidebar";
import { ROOT_FOLDER_ID } from "@/lib/constants";

export default async function MyDrivePage() {
  return (
    <Screen>
      <Sidebar />
      <Content parent={ROOT_FOLDER_ID} />
    </Screen>
  );
}
