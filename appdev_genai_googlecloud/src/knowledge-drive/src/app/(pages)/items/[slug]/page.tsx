import { getDownloadURL, getOwner, getSourceIP } from "@/lib/actions";
import { logWarn } from "@/lib/logging";
import { headers } from "next/headers";
import { notFound, redirect } from "next/navigation";

export default async function PerItemPage({
  params,
}: {
  params: { slug: string };
}) {
  const action = "showItemDetails";
  const headersList = headers();
  const owner = getOwner(headersList);
  const sourceIP = getSourceIP(headersList);
  const { slug: id } = params;

  const res = await getDownloadURL(id);
  console.log(res);

  if (!res.url) {
    logWarn({
      owner: owner,
      sourceIP: sourceIP,
      action: action,
      message: `${sourceIP}/${owner}/${action}/${id}: Failed to find item with id ${id}`,
    });
    return notFound();
  }

  redirect(res.url);
}
