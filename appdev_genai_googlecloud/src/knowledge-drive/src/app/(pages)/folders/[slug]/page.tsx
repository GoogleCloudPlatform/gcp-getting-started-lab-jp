import Content from "@/components/content";
import Screen from "@/components/screen";
import Sidebar from "@/components/sidebar";

export default async function FoldersPage({
  params,
}: {
  params: { slug: string };
}) {
  const { slug } = params;
  return (
    <Screen>
      <Sidebar />
      <Content parent={slug} />
    </Screen>
  );
}
