"use client";

import { useRouter } from "next/navigation";
import { useEffect } from "react";

type RefreshProps = {
  intervalSecond: number;
};

const Refresh = ({ intervalSecond }: RefreshProps) => {
  const router = useRouter();

  useEffect(() => {
    const id = setInterval(() => {
      console.log("refreshed");
      router.refresh();
    }, intervalSecond * 1000);
    return () => clearInterval(id);
  }, []);

  return <></>;
};

export default Refresh;
