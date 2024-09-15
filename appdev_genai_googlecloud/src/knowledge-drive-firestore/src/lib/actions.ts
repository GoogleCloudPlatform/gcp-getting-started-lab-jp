"use server";

import { GetSignedUrlConfig, Storage } from "@google-cloud/storage";
import { DEFAULT_OWNER, ROOT_FOLDER_ID } from "@/lib/constants";
import { TItem, FolderForBreadcrumb } from "@/lib/types";
import { logError, logInfo } from "@/lib/logging";
import { nanoid } from "nanoid";
import { ReadonlyHeaders } from "next/dist/server/web/spec-extension/adapters/headers";
import { headers } from "next/headers";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import firestoreAdminApp from "@/lib/firebase/admin";
import { printCreatedAtInJST } from "@/lib/utils";

const storage = new Storage();

const db = getFirestore(firestoreAdminApp);

export const createFolder = async (
  folderName: string | null,
  parent: string,
) => {
  const action = "createFolder";
  const headersList = headers();
  const owner = await getOwner(headersList);
  const sourceIP = await getSourceIP(headersList);
  const id = nanoid();
  await db.collection("users").doc(owner).collection("items").doc(id).set({
    id: id,
    name: folderName,
    isFolder: true,
    parent: parent,
    owner: owner,
    size: 0,
    createdAt: FieldValue.serverTimestamp(),
    embedded: false,
  });
  logInfo({
    owner: owner,
    sourceIP: sourceIP,
    action: action,
    message: `${sourceIP}/${owner}/${action}/${folderName}: Created a folder under ${parent}`,
  });
};

export const createFile = async (
  id: string,
  name: string,
  parent: string,
  size: number,
  contentType: string,
) => {
  const action = "createFile";
  const headersList = headers();
  const owner = await getOwner(headersList);
  const sourceIP = await getSourceIP(headersList);
  await db.collection("users").doc(owner).collection("items").doc(id).set({
    id: id,
    name: name,
    isFolder: false,
    parent: parent,
    owner: owner,
    type: contentType,
    size: size,
    createdAt: FieldValue.serverTimestamp(),
    embedded: false,
  });
  logInfo({
    owner: owner,
    sourceIP: sourceIP,
    action: action,
    message: `${sourceIP}/${owner}/${action}/${name}: Created a folder under ${parent}`,
  });
};

export const generateUploadSignedURL = async (
  id: string,
  filename: string,
  contentType: string,
) => {
  const action = "generateUploadSignedURL";
  const headersList = headers();
  const owner = await getOwner(headersList);
  const sourceIP = await getSourceIP(headersList);
  if (!process.env.BUCKET_NAME) {
    logError({
      owner: owner,
      sourceIP: sourceIP,
      action: action,
      message: `${sourceIP}/${owner}/${action}/${filename}: BUCKET_NAME is not defined`,
    });
    throw new Error("BUCKET_NAME is not defined");
  }
  const filepath = await createFilepathOnGCS(id, filename, owner);
  const options: GetSignedUrlConfig = {
    version: "v4",
    action: "write",
    expires: Date.now() + 1000 * 60 * 5, // 5 minutes
    contentType: contentType,
  };
  const [url] = await storage
    .bucket(process.env.BUCKET_NAME)
    .file(filepath)
    .getSignedUrl(options);
  logInfo({
    owner: owner,
    sourceIP: sourceIP,
    action: action,
    message: `${sourceIP}/${owner}/${action}/${filename}: Generated an upload signed URL`,
  });
  return url;
};

export const generateDownloadSignedURL = async (storagePath: string) => {
  const action = "generateDownloadSignedURL";
  const headersList = headers();
  const owner = await getOwner(headersList);
  const sourceIP = await getSourceIP(headersList);
  if (!process.env.BUCKET_NAME) {
    logError({
      owner: owner,
      sourceIP: sourceIP,
      action: action,
      message: `${sourceIP}/${owner}/${action}/${storagePath}: BUCKET_NAME is not defined`,
    });
    throw new Error("BUCKET_NAME is not defined");
  }
  const options: GetSignedUrlConfig = {
    version: "v4",
    action: "read",
    expires: Date.now() + 1000 * 60 * 5, // 5 minutes
  };
  const [url] = await storage
    .bucket(process.env.BUCKET_NAME)
    .file(storagePath)
    .getSignedUrl(options);
  logInfo({
    owner: owner,
    sourceIP: sourceIP,
    action: action,
    message: `${sourceIP}/${owner}/${action}/${storagePath}: Generated a download signed URL`,
  });
  return url;
};

export const searchItemsByQueryAndOwner = async (
  queryText: string,
  owner: string,
) => {
  const action = "searchItem";
  const headersList = headers();
  const sourceIP = await getSourceIP(headersList);
  const snapshot = await db
    .collection("users")
    .doc(owner)
    .collection("items")
    .where("name", "==", queryText)
    .get();
  logInfo({
    owner: owner,
    sourceIP: sourceIP,
    action: action,
    message: `${sourceIP}/${owner}/${action}/${queryText}: Searched items by ${queryText}`,
  });

  return convertFirestoreItemsSnapshotToTItem(snapshot);
};

const getItemByID = async (id: string, owner: string) => {
  const item = await db
    .collection("users")
    .doc(owner)
    .collection("items")
    .doc(id)
    .get();
  if (!item.exists) {
    return null;
  }
  return item.data();
};

export const createFilepathOnGCS = async (
  id: string,
  filename: string,
  owner: string,
) => {
  return `${owner}/${id}.${filename}`;
};

export const getDownloadURL = async (id: string) => {
  const headersList = headers();
  const owner = await getOwner(headersList);
  const item = await getItemByID(id, owner);
  if (!item) {
    return { url: "" };
  }
  const filename = await createFilepathOnGCS(id, item.name, owner);
  const downloadURL = await generateDownloadSignedURL(filename);

  return { url: downloadURL };
};

export const isFolderExist = async (
  id: string,
  owner: string,
): Promise<boolean> => {
  if (id === ROOT_FOLDER_ID) return true;

  const folder = await db
    .collection("users")
    .doc(owner)
    .collection("items")
    .doc(id)
    .get();
  return folder.exists;
};

export const getItemsByParentAndOwner = async (
  parent: string,
  owner: string,
) => {
  const action = "getItems";
  const headersList = headers();
  const sourceIP = await getSourceIP(headersList);
  const snapshot = await db
    .collection("users")
    .doc(owner)
    .collection("items")
    .where("parent", "==", parent)
    .orderBy("createdAt", "desc")
    .get();
  logInfo({
    owner: owner,
    sourceIP: sourceIP,
    action: action,
    message: `${sourceIP}/${owner}/${action}/${parent}: Get items by ${parent}`,
  });
  return convertFirestoreItemsSnapshotToTItem(snapshot);
};

export const getOwner = async (headers: ReadonlyHeaders): Promise<string> => {
  const userEmailHeaderValue = headers.get("x-goog-authenticated-user-email");
  if (!userEmailHeaderValue) {
    return DEFAULT_OWNER;
  }
  return userEmailHeaderValue.replace("accounts.google.com:", "");
};

export const getSourceIP = async (
  headers: ReadonlyHeaders,
): Promise<string> => {
  const ipHeaderValue = headers.get("x-forwarded-for");
  if (!ipHeaderValue) {
    return "unknown";
  }
  return ipHeaderValue;
};

export const getParents = async (
  id: string,
): Promise<FolderForBreadcrumb[]> => {
  const action = "getParents";
  const headersList = headers();
  const owner = await getOwner(headersList);
  const sourceIP = await getSourceIP(headersList);

  if (id === ROOT_FOLDER_ID) {
    return [{ id: ROOT_FOLDER_ID, name: "マイドライブ" }];
  }

  let count = 3;
  const items: FolderForBreadcrumb[] = [];
  let queryId = id;
  while (count > 0) {
    if (queryId === ROOT_FOLDER_ID) {
      items.unshift({
        id: ROOT_FOLDER_ID,
        name: "マイドライブ",
      });
      break;
    }
    const item = await db
      .collection("users")
      .doc(owner)
      .collection("items")
      .doc(queryId)
      .get();
    const data = item.data();
    if (!data) {
      break;
    }
    items.unshift({
      id: data.id as string,
      name: data.name as string,
    });
    queryId = data.parent as string;
    count--;
  }
  logInfo({
    owner: owner,
    sourceIP: sourceIP,
    action: action,
    message: `${sourceIP}/${owner}/${action}/${id}: Get parents by ${id} and found ${items.length} folders`,
  });
  return items;
};

export const convertFirestoreItemsSnapshotToTItem = (
  snapshot: FirebaseFirestore.QuerySnapshot<
    FirebaseFirestore.DocumentData,
    FirebaseFirestore.DocumentData
  >,
): TItem[] => {
  const tItems: TItem[] = [];
  snapshot.forEach((doc) => {
    const data = doc.data();
    tItems.push({
      id: data.id as string,
      name: data.name as string,
      size: data.size as number,
      type: data.type ? (data.type as string) : null,
      isFolder: data.isFolder as boolean,
      createdAt: printCreatedAtInJST(data.createdAt.toDate()),
      parent: data.parent ? (data.parent as string) : null,
      owner: data.owner as string,
      description: data.description ? (data.description as string) : null,
      embedded: data.embedded as boolean,
    });
  });
  return tItems;
};
