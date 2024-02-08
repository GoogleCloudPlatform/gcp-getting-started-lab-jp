export type ItemSelector = {
  text: string;
};

export type TItem = {
  id: string;
  name: string;
  size: number | null;
  type: string | null;
  isFolder: boolean;
  createdAt: string;
  parent: string | null;
  owner: string | null;
  description: string | null;
};

export type DBItem = {
  id: string;
  name: string;
  size: number | null;
  type: string | null;
  is_folder: boolean;
  created_at: Date;
  parent: string | null;
  owner: string | null;
  description: string | null;
};
