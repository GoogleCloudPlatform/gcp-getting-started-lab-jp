"use client";

import { AiOutlinePlus } from "react-icons/ai";
import { Button } from "./ui/button";
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
} from "./ui/dropdown-menu";
import { AiOutlineFolderAdd } from "react-icons/ai";
import { GrDocumentUpload } from "react-icons/gr";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "./ui/dialog";
import { Input } from "./ui/input";
import * as z from "zod";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Form, FormControl, FormField, FormItem, FormMessage } from "./ui/form";
import { useState } from "react";
import { usePathname } from "next/navigation";
import { createFile, createFolder } from "@/lib/firebase/firestore";
import { User } from "firebase/auth";
import { getFolderId } from "@/lib/utils";
import { Label } from "./ui/label";
import { alphanumeric } from "nanoid-dictionary";
import { customAlphabet } from "nanoid";
import {
  getDownloadURL,
  getStorage,
  ref,
  uploadBytesResumable,
} from "firebase/storage";
import firebaseClientApp from "@/lib/firebase/client";
import { toast } from "react-hot-toast";

const storage = getStorage(firebaseClientApp);

const formSchema = z.object({
  folderName: z.string().min(3).max(20),
});

type NewButtonProps = {
  user: User;
};

const NewButton = ({ user }: NewButtonProps) => {
  const pathname = usePathname();

  const [dialogOpen, setDialogOpen] = useState(false);
  const [dropdownMenuOpen, setDropdownMenuOpen] = useState(false);

  const form = useForm<z.infer<typeof formSchema>>({
    resolver: zodResolver(formSchema),
    defaultValues: {
      folderName: "",
    },
  });

  const handleUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    if (!e.target.files) return;
    const file = e.target.files[0];
    const fileId = customAlphabet(alphanumeric, 20)();
    var fileExtension = file.name.split(".").pop();
    const filePath = `/files/${user.uid}/${fileId}.${fileExtension}`;
    const storageRef = ref(storage, filePath);

    const uploadTask = uploadBytesResumable(storageRef, file, {
      contentType: file.type,
    });

    setDropdownMenuOpen(false);
    uploadTask.on(
      "state_changed",
      (snapshot) => {
        const progress =
          (snapshot.bytesTransferred / snapshot.totalBytes) * 100;
        console.log("upload is " + progress + "% done");
        switch (snapshot.state) {
          case "paused":
            console.log("upload is paused");
            break;
          case "running":
            console.log("upload is running");
            break;
        }
      },
      (error) => {
        switch (error.code) {
          case "storage/unauthorized":
            console.log("NO PERMISSION");
            break;
          case "storage/canceled":
            break;
          case "storage/unknown":
            break;
        }
        toast.error("ファイルのアップロードに失敗しました");
      },
      () => {
        console.log("upload finished!!");
        getDownloadURL(uploadTask.snapshot.ref).then((downloadURL) => {
          createFile({
            id: fileId,
            name: file.name,
            parent: getFolderId(pathname),
            uid: user.uid,
            size: file.size,
            url: downloadURL,
          });
        });
        toast.success("ファイルのアップロードが完了しました");
      }
    );
  };

  const onSubmit = async (values: z.infer<typeof formSchema>) => {
    form.reset();
    setDialogOpen(false);
    await createFolder({
      name: values.folderName,
      parent: getFolderId(pathname),
      uid: user.uid,
    });
  };

  return (
    <div className="grid-in-newb max-w-[256px] px-4 pt-2 pb-4">
      <div>
        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
          <DropdownMenu
            open={dropdownMenuOpen}
            onOpenChange={setDropdownMenuOpen}
          >
            <DropdownMenuTrigger>
              <div className="items-center flex gap-3 bg-white h-14 text-black cursor-pointer min-w-[100px] rounded-xl drop-shadow-md py-[18px] pl-4 pr-5 hover:bg-[#edf2fc]">
                <AiOutlinePlus size={24} />
                <span>新規</span>
              </div>
            </DropdownMenuTrigger>
            <DropdownMenuContent sideOffset={-40} className="ml-4">
              <div className="h-22 w-[240px] flex-col flex text-[14px] gap-2">
                <DialogTrigger>
                  <div
                    className="mt-2 px-2 h-8 hover:bg-slate-100 flex items-center gap-3"
                    onClick={() => setDropdownMenuOpen(false)}
                  >
                    <AiOutlineFolderAdd size={24} />
                    <span>新しいフォルダ</span>
                  </div>
                </DialogTrigger>
                <Label
                  htmlFor="file"
                  className="mb-2 pl-[10px] h-8 hover:bg-slate-100 flex items-center gap-3"
                >
                  <Input
                    type="file"
                    className="opacity-0 absolute left-[-9999px]"
                    onChange={handleUpload}
                    id="file"
                  />
                  <GrDocumentUpload size={20} />
                  <span>ファイルのアップロード</span>
                </Label>
              </div>
            </DropdownMenuContent>
          </DropdownMenu>
          <DialogContent>
            <DialogHeader>
              <DialogTitle className="text-[24px]">新しいフォルダ</DialogTitle>
            </DialogHeader>
            <Form {...form}>
              <form
                onSubmit={form.handleSubmit(onSubmit)}
                className="space-y-8"
              >
                <FormField
                  control={form.control}
                  name="folderName"
                  render={({ field }) => (
                    <FormItem>
                      <FormControl>
                        <Input placeholder="無題のフォルダ" {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
                <DialogFooter>
                  <Button
                    type="reset"
                    variant="ghost"
                    onClick={() => form.reset()}
                  >
                    リセット
                  </Button>
                  <Button type="submit" variant="ghost">
                    作成
                  </Button>
                </DialogFooter>
              </form>
            </Form>
          </DialogContent>
        </Dialog>
      </div>
    </div>
  );
};

export default NewButton;
