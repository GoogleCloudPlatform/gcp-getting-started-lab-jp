import firebaseClientApp from "../../libs/firebase/client";
import { ClipLoader } from "react-spinners";
import { useDocument } from "react-firebase-hooks/firestore";
import { doc, getFirestore } from "firebase/firestore";
import AvatarIcon from "./AvatarIcon";

const firestore = getFirestore(firebaseClientApp);

type Props = {
  uid: string;
};

const CurrentUserAvatar = ({ uid }: Props) => {
  const [value, loading] = useDocument(doc(firestore, "users", uid));

  if (loading || !value) {
    return (
      <div className="flex w-6 h-6 relative bg-white rounded-full">
        <ClipLoader className="m-auto" color="#888888" size={20} />
      </div>
    );
  }

  return (
    <>
      <AvatarIcon
        bgColor={"bg-" + value.data()?.color}
        animal={value.data()?.animal}
      />
    </>
  );
};

export default CurrentUserAvatar;
