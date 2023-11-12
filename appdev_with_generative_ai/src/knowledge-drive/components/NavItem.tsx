import { useRouter } from "next/navigation";

type NavItemProps = {
  title: string;
  children: React.ReactNode;
  path: string;
  disabled: boolean;
};

const NavItem = ({ title, children, path, disabled }: NavItemProps) => {
  const router = useRouter();

  const handleClick = () => {
    if (disabled) return;

    router.push(path);
  };

  return (
    <div
      className={`h-8 relative w-full rounded-full flex items-center px-[3px] ${
        disabled ? "" : "cursor-pointer hover:bg-gray-200"
      }`}
      onClick={handleClick}
    >
      <div className="h-7 mt-0 min-w-0 pl-[3px] flex-auto align-top">
        <div className="flex h-full items-center leading-[26px] align-middle">
          <div className="pr-[14px] ml-[14px] align-middle leading-normal flex-none">
            <div className="h-5 w-5 bg-no-repeat leading-normal">
              {children}
            </div>
          </div>
          <span className="text-sm flex-auto inline-block align-middle truncate leading-[26px] pr-4">
            {title}
          </span>
        </div>
      </div>
    </div>
  );
};

export default NavItem;
