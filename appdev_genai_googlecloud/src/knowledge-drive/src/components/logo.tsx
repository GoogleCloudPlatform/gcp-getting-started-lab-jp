import Image from "next/image";

const Logo = () => {
  return (
    <div className="relative h-12 w-12">
      <Image src="/images/logo.png" fill alt="Logo" sizes="20vw" />
    </div>
  );
};

export default Logo;
