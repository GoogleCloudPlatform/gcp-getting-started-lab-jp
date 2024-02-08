import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";
import { ROOT_FOLDER_ID } from "./constants";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export const printCreatedAtInJST = (dateString: string) => {
  const timeInJST = new Date(dateString).toLocaleString("ja-JP", {
    timeZone: "Asia/Tokyo",
  });
  const [year, month, day] = timeInJST.split(" ")[0].split("/");
  const formattedTime = `${year}年${month}月${day}日`;
  return formattedTime;
};

export const printFilesize = (filesize: number | null) => {
  if (!filesize) return "";
  if (filesize >= 1024 * 1024 * 1024)
    return (filesize / (1024 * 1024 * 1024)).toFixed(2).toString() + " GB";
  if (filesize >= 1024 * 1024)
    return (filesize / (1024 * 1024)).toFixed(2).toString() + " MB";
  if (filesize >= 1024) return (filesize / 1024).toFixed(2).toString() + " KB";
  return filesize.toString() + " B";
};

export const getParentFromPath = (pathname: string): string => {
  if (pathname === "/my-drive" || pathname === "/search") return ROOT_FOLDER_ID;
  return pathname.replace("/folders/", "");
};
