"use server";

import { GetSignedUrlConfig, Storage } from "@google-cloud/storage";
import { DEFAULT_OWNER, ROOT_FOLDER_ID } from "@/lib/constants";
import { createPoolWithConnector } from "@/lib/db";
import { DBItem, TItem } from "@/lib/types";
import { printCreatedAtInJST } from "@/lib/utils";
import { logError, logInfo } from "@/lib/logging";
import { nanoid } from "nanoid";
import { ReadonlyHeaders } from "next/dist/server/web/spec-extension/adapters/headers";
import { headers } from "next/headers";

const storage = new Storage();

export const createFolder = async (
  folderName: string | null,
  parent: string,
) => {
  const action = "createFolder";
  const headersList = headers();
  const owner = await getOwner(headersList);
  const sourceIP = await getSourceIP(headersList);
  const id = nanoid();
  const query = `INSERT INTO items(id, name, is_folder, parent, owner) VALUES ($1, $2, $3, $4, $5)`;
  const values = [id, folderName, true, parent, owner];
  const pool = await createPoolWithConnector();
  await pool.query(query, values);
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
  const query = `INSERT INTO items(id, name, is_folder, size, type, parent, owner) VALUES ($1, $2, $3, $4, $5, $6, $7)`;
  const values = [id, name, false, size, contentType, parent, owner];
  const pool = await createPoolWithConnector();
  await pool.query(query, values);
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
  const query = `SELECT * FROM items WHERE owner = $1 AND name ILIKE $2 ORDER BY created_at DESC`;
  const values = [owner, "%" + queryText + "%"];
  const pool = await createPoolWithConnector();
  const { rows } = await pool.query(query, values);
  logInfo({
    owner: owner,
    sourceIP: sourceIP,
    action: action,
    message: `${sourceIP}/${owner}/${action}/${queryText}: Searched items by ${queryText}`,
  });
  return convertDBItemsToDBItems(rows as DBItem[]);
};

const convertDBItemsToDBItems = async (dbItems: DBItem[]): Promise<TItem[]> => {
  return dbItems.map((dbItem) => {
    return {
      id: dbItem.id,
      name: dbItem.name,
      size: dbItem.size,
      type: dbItem.type,
      parent: dbItem.parent,
      owner: dbItem.owner,
      createdAt: printCreatedAtInJST(dbItem.created_at.toISOString()),
      isFolder: dbItem.is_folder,
      description: dbItem.description,
    };
  });
};

export const getItemByID = async (id: string, owner: string) => {
  const query = `SELECT * FROM items WHERE id = $1 AND owner = $2`;
  const values = [id, owner];
  const pool = await createPoolWithConnector();
  const { rows } = await pool.query(query, values);
  const convertedRows = await convertDBItemsToDBItems(rows as DBItem[]);
  if (convertedRows.length === 0) {
    return null;
  }
  return convertedRows[0];
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

export const isFolderExist = async (id: string, owner: string) => {
  if (id === ROOT_FOLDER_ID) return true;

  const query = `SELECT * FROM items WHERE id = $1 AND owner = $2 AND is_folder = true`;
  const values = [id, owner];
  const pool = await createPoolWithConnector();
  const { rows } = await pool.query(query, values);
  return rows.length === 1;
};

export const getItemsByParentAndOwner = async (
  parent: string,
  owner: string,
) => {
  const action = "getItems";
  const headersList = headers();
  const sourceIP = await getSourceIP(headersList);
  const query = `SELECT * FROM items WHERE parent = $1 AND owner = $2 ORDER BY created_at DESC`;
  const values = [parent, owner];
  const pool = await createPoolWithConnector();
  const { rows } = await pool.query(query, values);
  logInfo({
    owner: owner,
    sourceIP: sourceIP,
    action: action,
    message: `${sourceIP}/${owner}/${action}/${parent}: Get items by ${parent}`,
  });
  return convertDBItemsToDBItems(rows as DBItem[]);
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

export const getParents = async (id: string) => {
  const action = "getParents";
  const headersList = headers();
  const owner = await getOwner(headersList);
  const sourceIP = await getSourceIP(headersList);
  const query = `WITH RECURSIVE parents AS (
    SELECT id, name, parent, 1 AS level
    FROM items
    WHERE id = $1
 
    UNION ALL
 
    SELECT f.id, f.name, f.parent, p.level + 1
    FROM items f
    JOIN parents p ON f.id = p.parent
    WHERE p.level < 3 AND p.id != $2
  )
  SELECT id, name, parent FROM parents ORDER BY level DESC`;
  const values = [id, ROOT_FOLDER_ID];
  const pool = await createPoolWithConnector();
  const { rows } = await pool.query(query, values);
  if (rows.length < 3) {
    rows.unshift({ id: ROOT_FOLDER_ID, name: "マイドライブ", parent: null });
  }
  logInfo({
    owner: owner,
    sourceIP: sourceIP,
    action: action,
    message: `${sourceIP}/${owner}/${action}/${id}: Get parents by ${id} and found ${rows.length} folders`,
  });
  return rows;
};
