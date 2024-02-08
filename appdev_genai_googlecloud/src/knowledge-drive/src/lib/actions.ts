"use server";

import { GetSignedUrlConfig, Storage } from "@google-cloud/storage";
import { DEFAULT_OWNER, ROOT_FOLDER_ID } from "@/lib/constants";
import { createPoolWithConnector } from "@/lib/db";
import { DBItem, TItem } from "@/lib/types";
import { nanoid } from "nanoid";
import { printCreatedAtInJST } from "./utils";
import { ReadonlyHeaders } from "next/dist/server/web/spec-extension/adapters/headers";
import { headers } from "next/headers";

const storage = new Storage();

export const createFolder = async (
  folderName: string | null,
  parent: string,
) => {
  const headersList = headers();
  const owner = getOwner(headersList);
  const id = nanoid();
  const query = `INSERT INTO items(id, name, is_folder, parent, owner) VALUES ($1, $2, $3, $4, $5)`;
  const values = [id, folderName, true, parent, owner];
  const pool = await createPoolWithConnector();
  await pool.query(query, values);
};

export const createFile = async (
  id: string,
  name: string,
  parent: string,
  size: number,
  contentType: string,
) => {
  const headersList = headers();
  const owner = getOwner(headersList);
  const query = `INSERT INTO items(id, name, is_folder, size, type, parent, owner) VALUES ($1, $2, $3, $4, $5, $6, $7)`;
  const values = [id, name, false, size, contentType, parent, owner];
  const pool = await createPoolWithConnector();
  await pool.query(query, values);
};

export const generateUploadSignedURL = async (
  id: string,
  filename: string,
  contentType: string,
) => {
  if (!process.env.BUCKET_NAME) {
    throw new Error("BUCKET_NAME is not defined");
  }
  const headersList = headers();
  const owner = getOwner(headersList);
  const filepath = createFilepathOnGCS(id, filename, owner);
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
  return url;
};

export const generateDownloadSignedURL = async (storagePath: string) => {
  if (!process.env.BUCKET_NAME) {
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
  return url;
};

export const searchItemsByQueryAndOwner = async (
  queryText: string,
  owner: string,
) => {
  const query = `SELECT * FROM items WHERE owner = $1 AND name ILIKE $2 ORDER BY created_at DESC`;
  const values = [owner, "%" + queryText + "%"];
  const pool = await createPoolWithConnector();
  const { rows } = await pool.query(query, values);
  return convertDBItemsToDBItems(rows as DBItem[]);
};

const convertDBItemsToDBItems = (dbItems: DBItem[]): TItem[] => {
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
  const convertedRows = convertDBItemsToDBItems(rows as DBItem[]);
  if (convertedRows.length === 0) {
    return null;
  }
  return convertedRows[0];
};

export const createFilepathOnGCS = (
  id: string,
  filename: string,
  owner: string,
) => {
  return `${owner}/${id}.${filename}`;
};

export const getDownloadURL = async (id: string) => {
  const headersList = headers();
  const owner = getOwner(headersList);
  const item = await getItemByID(id, owner);
  if (!item) {
    return { url: "" };
  }
  const filename = createFilepathOnGCS(id, item.name, owner);
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
  const query = `SELECT * FROM items WHERE parent = $1 AND owner = $2 ORDER BY created_at DESC`;
  const values = [parent, owner];
  const pool = await createPoolWithConnector();
  const { rows } = await pool.query(query, values);
  return convertDBItemsToDBItems(rows as DBItem[]);
};

export const getOwner = (headers: ReadonlyHeaders): string => {
  const userEmailHeaderValue = headers.get("x-goog-authenticated-user-email");
  if (!userEmailHeaderValue) {
    return DEFAULT_OWNER;
  }
  return userEmailHeaderValue.replace("accounts.google.com:", "");
};

export const getParents = async (id: string) => {
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
  return rows;
};
