import { getOwner } from "@/lib/actions";
import { getAvatarColor } from "@/lib/color";
import { DEFAULT_OWNER, MY_DRIVE_URL } from "@/lib/constants";
import { headers } from "next/headers";
import Link from "next/link";
import { FaUser } from "react-icons/fa6";

const Avatar = () => {
  const headersList = headers();
  const owner = getOwner(headersList);
  const color = getAvatarColor(owner);
  const bgColor = `bg-${color}`;

  return (
    <div className="ml-auto mr-1 flex h-12 w-12 items-center justify-center">
      {owner === DEFAULT_OWNER ? (
        <div className="flex h-8 w-8 items-center justify-center rounded-full bg-slate-500 text-lg text-white">
          <FaUser />
        </div>
      ) : (
        <Link href={`/_gcp_iap/clear_login_cookie`} prefetch={false}>
          <div
            className={`flex h-8 w-8 items-center justify-center rounded-full ${bgColor} text-lg text-white`}
          >
            {owner.charAt(0).toUpperCase()}
          </div>
        </Link>
      )}
    </div>
  );
};

export default Avatar;
