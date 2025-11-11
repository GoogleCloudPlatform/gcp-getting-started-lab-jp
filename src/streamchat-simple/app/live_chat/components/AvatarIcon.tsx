import React from "react";
import Image from "next/image";

type Props = {
  bgColor: string;
  animal: string;
};

const AvatarIcon = ({ bgColor, animal }: Props) => {
  return (
    <>
      <div className={`flex-none w-6 h-6 relative ${bgColor} rounded-full`}>
        <Image
          src={"/images/" + animal + ".png"}
          alt="avatar"
          sizes="100vw"
          fill
          className="rounded-full p-[2px]"
        />
      </div>
    </>
  );
};

export default AvatarIcon;
