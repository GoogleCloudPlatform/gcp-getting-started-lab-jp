import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";
import ToasterContext from "@/context/toaster-context";
import Providers from "@/providers/query-client";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: "Knowledge Drive",
  description: "Store your knowledge into Cloud",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body
        className={`${inter.className} flex h-screen w-screen flex-col bg-thick`}
      >
        <Providers>
          {children}
          <ToasterContext />
        </Providers>
      </body>
    </html>
  );
}
