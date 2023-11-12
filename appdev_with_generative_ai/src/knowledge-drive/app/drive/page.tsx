"use client";

import { useEffect, useState } from "react";
import { useAuthState } from "react-firebase-hooks/auth";
import { getAuth } from "firebase/auth";
import { useRouter } from "next/navigation";

import firebaseClientApp from "@/lib/firebase/client";
import LoadingPage from "@/components/ui/LoadingPage";
import Header from "@/components/Header";
import Navbar from "@/components/Navbar";
import NewButton from "@/components/NewButton";
import Main from "@/components/Main";

const auth = getAuth(firebaseClientApp);

const DrivePage = () => {
  const [csrfToken, setCsrfToken] = useState("loading...");
  const [user, loading] = useAuthState(auth);

  const router = useRouter();

  useEffect(() => {
    const el = document.querySelector(
      'meta[name="x-csrf-token"]'
    ) as HTMLMetaElement | null;
    if (el) setCsrfToken(el.content);
    else setCsrfToken("missing");
  }, []);

  if (loading) {
    return <LoadingPage />;
  }

  if (!user) {
    return router.push("/");
  }
  return (
    <>
      <div className="flex flex-col h-screen">
        <div className="grid grid-areas-layout grid-cols-layout grid-rows-layout h-full">
          <Header user={user} csrfToken={csrfToken} />
          <NewButton user={user} />
          <Navbar />
          <Main user={user} />
        </div>
      </div>
    </>
  );
};

export default DrivePage;
