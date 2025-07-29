"use client";

import { ChangeEvent, useCallback, useState } from "react";
import { useRouter } from "next/navigation";

import { toast } from "react-hot-toast";
import Input from "./Input";
import Button from "./Button";
import { signUp, signIn } from "@/app/libs/firebase/auth";

type Variant = "LOGIN" | "REGISTER";

type Props = {
  csrfToken: string;
};

const AuthForm = ({ csrfToken }: Props) => {
  const router = useRouter();
  const [variant, setVariant] = useState<Variant>("LOGIN");
  const [isLoading, setIsLoading] = useState(false);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");

  const handleNameChange = (e: ChangeEvent<HTMLInputElement>) => {
    setName(e.target.value);
  };

  const handleEmailChange = (e: ChangeEvent<HTMLInputElement>) => {
    setEmail(e.target.value);
  };

  const handlePasswordChange = (e: ChangeEvent<HTMLInputElement>) => {
    setPassword(e.target.value);
  };

  const toggleVariant = useCallback(() => {
    if (variant === "LOGIN") {
      setVariant("REGISTER");
    } else {
      setVariant("LOGIN");
    }
  }, [variant]);

  const handleSubmit = (
    tokenVal: string
  ): React.FormEventHandler<HTMLFormElement> => {
    return async (event: React.FormEvent<HTMLFormElement>) => {
      event.preventDefault();
      setIsLoading(true);
      if (variant === "REGISTER") {
        try {
          await signUp(
            {
              name: name,
              email: email,
              password: password,
            },
            tokenVal
          );
          return router.push("/live_chat");
        } catch (e) {
          console.error(e);
          toast.error("Failed to sign up");
        } finally {
          setIsLoading(false);
        }
      } else {
        try {
          await signIn({ email: email, password: password });
          return router.push("/live_chat");
        } catch (e) {
          console.error(e);
          toast.error("Failed to sign in");
        } finally {
          setIsLoading(false);
        }
      }
    };
  };

  return (
    <div className="mt-8 sm:mx-auto sm:w-full sm:max-w-md">
      <div
        className="
        bg-white
        dark:bg-gray-900
          px-4
          py-8
          shadow
          sm:rounded-lg
          sm:px-10
        "
      >
        <form className="space-y-6" onSubmit={handleSubmit(csrfToken)}>
          {variant === "REGISTER" && (
            <Input
              disabled={isLoading}
              required
              id="name"
              label="ユーザー名 / Username"
              value={name}
              onChange={handleNameChange}
              minLength={3}
              maxLength={20}
            />
          )}
          <Input
            disabled={isLoading}
            required
            id="email"
            label="メールアドレス / E-mail"
            type="email"
            value={email}
            onChange={handleEmailChange}
            minLength={5}
            maxLength={30}
          />
          <Input
            disabled={isLoading}
            required
            id="password"
            label="パスワード / Password"
            type="password"
            value={password}
            onChange={handlePasswordChange}
            minLength={6}
            maxLength={30}
          />
          <div>
            <Button disabled={isLoading} fullWidth type="submit">
              {variant === "LOGIN" ? "サインイン / Sign in" : "登録 / Register"}
            </Button>
          </div>
        </form>
        <div
          className="
            flex 
            gap-2 
            justify-center 
            text-sm 
            mt-6 
            px-2 
          "
        >
          <div className="text-black dark:text-gray-300">
            {variant === "LOGIN"
              ? "初めての方は?"
              : "既にアカウントを持っている方は?"}
          </div>
          <div
            onClick={toggleVariant}
            className="underline cursor-pointer text-black dark:text-gray-300"
          >
            {variant === "LOGIN" ? "アカウントを登録する" : "サインイン"}
          </div>
        </div>
      </div>
    </div>
  );
};

export default AuthForm;
