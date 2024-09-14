import Image from "next/image";

type EmptyListProps = {
  children: React.ReactNode;
};

const EmptyList = ({ children }: EmptyListProps) => {
  return (
    <div className="flex h-full w-full flex-col items-center justify-center">
      <div className="flex h-[200px] w-[200px] items-center justify-center rounded-full bg-gray-100">
        <Image
          src="/images/notfound.png"
          width={200}
          height={200}
          alt="NotFound"
        />
      </div>
      {children}
    </div>
  );
};

export default EmptyList;
