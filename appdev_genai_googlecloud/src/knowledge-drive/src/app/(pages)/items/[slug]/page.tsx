import { getDownloadURL } from "@/lib/actions";
import { notFound, redirect } from "next/navigation";

export default async function PerItemPage({
  params,
}: {
  params: { slug: string };
}) {
  const { slug: id } = params;

  const res = await getDownloadURL(id);
  console.log(res);

  if (!res.url) {
    console.log("here");
    return notFound();
  }

  redirect(res.url);
}
