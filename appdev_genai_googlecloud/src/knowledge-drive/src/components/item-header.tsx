import { BsThreeDotsVertical } from "react-icons/bs";
const ItemHeader = () => {
  return (
    <div className="flex h-12 items-center gap-x-2 border-b border-gray-300 pt-2">
      <p className="mr-auto min-w-[216px]">名前</p>
      <p className="w-32 min-w-32">オーナー</p>
      <p className="w-28 min-w-28">作成日時</p>
      <p className="w-32 min-w-32">ファイルサイズ</p>
      <BsThreeDotsVertical />
    </div>
  );
};

export default ItemHeader;
