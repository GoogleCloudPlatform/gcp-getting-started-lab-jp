"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";

type LinkItemProps = {
  icon: React.ReactNode;
  description: string;
  url: string;
  marginBottom?: boolean;
  disabled?: boolean;
};

const LinkItem = ({
  icon,
  description,
  url,
  marginBottom = false,
  disabled = false,
}: LinkItemProps) => {
  const pathname = usePathname();

  if (disabled) {
    return (
      <div
        className={cn(
          "ml-[14px] flex h-8 w-[224px] items-center gap-x-2 rounded-full pl-4",
          {
            "mb-4": marginBottom,
          },
        )}
      >
        {icon}
        <p className="ml-2 text-sm text-default">{description}</p>
      </div>
    );
  }

  return (
    <Link
      href={url}
      className={cn(
        "ml-[14px] flex h-8 w-[224px] items-center gap-x-2 rounded-full pl-4 transition",
        {
          "mb-4": marginBottom,
          "bg-blueselected": pathname === url,
          "hover:bg-[#e4e5e9]": pathname !== url,
          "pointer-events-none": disabled,
        },
      )}
      aria-disabled={disabled}
      tabIndex={disabled ? -1 : undefined}
    >
      {icon}
      <p className="ml-2 text-sm text-default">{description}</p>
    </Link>
  );
};

export default LinkItem;
