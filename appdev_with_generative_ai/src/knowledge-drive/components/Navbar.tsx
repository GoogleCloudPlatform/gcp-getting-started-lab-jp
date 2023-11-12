import { FiHardDrive } from "react-icons/fi";
import NavItem from "./NavItem";
import { FaComputer } from "react-icons/fa6";
import { HiUsers } from "react-icons/hi";
import {
  AiOutlineClockCircle,
  AiOutlineCloud,
  AiOutlineStar,
} from "react-icons/ai";
import { RiSpam2Line } from "react-icons/ri";
import { BsTrash } from "react-icons/bs";

const Navbar = () => {
  return (
    <div className="grid-in-nav min-w-[256px] max-w-[394px] border-r-1 overflow-hidden">
      <div className="flex w-full h-full overflow-visible">
        <div className="flex p-0 mr-[6px] overflow-x-hidden overflow-y-auto">
          <div className="ml-4 overflow-auto invisible">
            <div className="mr-[10px] visible">
              <nav className="visible">
                <div className="w-full relative min-h-[80px] overflow-hidden">
                  <NavItem title="マイドライブ" path="/drive" disabled={false}>
                    <FiHardDrive size={20} />
                  </NavItem>
                  <NavItem title="パソコン" path="/my-drive" disabled>
                    <FaComputer size={20} />
                  </NavItem>
                  <NavItem title="共有アイテム" path="/my-drive" disabled>
                    <HiUsers size={20} />
                  </NavItem>
                  <NavItem
                    title="最近使用したアイテム"
                    path="/my-drive"
                    disabled
                  >
                    <AiOutlineClockCircle size={20} />
                  </NavItem>
                  <NavItem title="スター付き" path="/my-drive" disabled>
                    <AiOutlineStar size={20} />
                  </NavItem>
                  <NavItem title="スパム" path="/my-drive" disabled>
                    <RiSpam2Line size={20} />
                  </NavItem>
                  <NavItem title="ゴミ箱" path="/my-drive" disabled>
                    <BsTrash size={20} />
                  </NavItem>
                  <NavItem title="保存容量" path="/my-drive" disabled>
                    <AiOutlineCloud size={20} />
                  </NavItem>
                </div>
              </nav>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Navbar;
