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
  embedded: boolean;
};

export type FolderForBreadcrumb = {
  id: string;
  name: string;
};
