import { Label } from "@/components/ui/label";
import { createFile, generateUploadSignedURL } from "@/lib/actions";
import { GrDocumentUpload } from "react-icons/gr";
import { toast } from "react-hot-toast";
import { nanoid } from "nanoid";
import { usePathname, useRouter } from "next/navigation";
import { getParentFromPath } from "@/lib/utils";

const UPLOAD_FILE = "uploadFile";

type FileUploadButtonProps = {
  closeDropdownMenu: () => void;
};

const FileUploadButton = ({ closeDropdownMenu }: FileUploadButtonProps) => {
  const pathname = usePathname();
  const router = useRouter();

  const uploadFile = async (
    signedURL: string,
    file: File,
    contentType: string,
  ) => {
    const res = await fetch(signedURL, {
      method: "PUT",
      body: file,
      headers: {
        "Content-Type": contentType,
      },
    });
    if (!res.ok) throw new Error("failed to upload file");
  };

  const handleUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    if (!e.target.files) return;

    const file = e.target.files[0];
    const contentType = file.type;
    const parent = getParentFromPath(pathname);

    toast("ファイルをアップロードを開始しました", {
      id: UPLOAD_FILE,
    });
    closeDropdownMenu();

    const id = nanoid();
    try {
      const signedURL = await generateUploadSignedURL(
        id,
        file.name,
        contentType,
      );
      await uploadFile(signedURL, file, contentType);
      await createFile(id, file.name, parent, file.size, contentType);

      toast.success("ファイルのアップロードが完了しました", {
        id: UPLOAD_FILE,
      });
      router.refresh();
    } catch (error) {
      toast.error("ファイルのアップロードに失敗しました", {
        id: UPLOAD_FILE,
      });
      console.error(error);
    }
  };

  return (
    <Label
      htmlFor="file"
      className="mb-2 flex h-8 items-center gap-3 pl-[10px] hover:bg-slate-200"
    >
      <input
        type="file"
        className="absolute left-[-9999px] opacity-0"
        onChange={handleUpload}
        name="file"
        id="file"
        accept="*"
      />
      <GrDocumentUpload size={20} />
      <p>ファイルのアップロード</p>
    </Label>
  );
};

export default FileUploadButton;
