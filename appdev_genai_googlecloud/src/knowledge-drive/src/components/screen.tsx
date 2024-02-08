import Header from "@/components/header";

type ScreenProps = {
  children: React.ReactNode;
};

const Screen = ({ children }: ScreenProps) => {
  return (
    <>
      <Header />
      <main className="flex flex-1 overflow-hidden">{children}</main>
    </>
  );
};

export default Screen;
