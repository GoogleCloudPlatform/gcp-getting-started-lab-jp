import AuthForm from "./components/AuthForm";
import { FcLock } from "react-icons/fc";

const Auth = () => {
  return (
    <div
      className="
        flex 
        h-screen
        flex-col 
        justify-center 
        py-12 
        sm:px-6 
        lg:px-8 
        bg-gray-100
      "
    >
      <div className="sm:mx-auto sm:w-full sm:max-w-md">
        <FcLock className="mx-auto w-auto" size={60} />
        <h2
          className="
            mt-6 
            text-center 
            text-3xl 
            font-bold 
            tracking-tight 
            text-gray-900
          "
        >
          Welcome to Stream Chat
        </h2>
      </div>
      <AuthForm />
    </div>
  );
};

export default Auth;
