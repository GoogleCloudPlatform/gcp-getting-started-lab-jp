import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export const printFilesize = (filesize: number) => {
  if (filesize >= 1024 * 1024 * 1024)
    return (filesize / (1024 * 1024 * 1024)).toFixed(2).toString() + " GB";
  if (filesize >= 1024 * 1024)
    return (filesize / (1024 * 1024)).toFixed(2).toString() + " MB";
  if (filesize >= 1024) return (filesize / 1024).toFixed(2).toString() + " KB";
  return filesize.toString() + " B";
};

export const printTimestamp = (timestamp: Date) => {
  if (!timestamp) return "";
  return (
    timestamp.getFullYear().toString() +
    "年" +
    (timestamp.getMonth() + 1).toString() +
    "月" +
    timestamp.getDate().toString() +
    "日"
  );
};

export const getFolderId = (pathname: string) => {
  if (pathname === "/drive") return "ROOT_FOLDER";
  return pathname.replace("/folders", "");
};

export const isSearchPage = (pathname: string) => {
  return pathname === "/search";
};
