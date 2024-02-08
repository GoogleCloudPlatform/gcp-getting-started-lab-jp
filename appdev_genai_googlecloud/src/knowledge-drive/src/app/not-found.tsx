import Image from "next/image";

function NotFoundPage() {
  return (
    <main className="flex h-screen justify-center">
      <div className="mt-36 flex w-[580px] gap-x-4">
        <section className="flex-1">
          <div className="relative h-24 w-24">
            <Image src="/images/logo.png" fill alt="Logo" sizes="20vw" />
          </div>
          <p className="text-gray-500">
            <span className="font-bold text-black">404.</span>{" "}
            エラーが発生しました。
          </p>
          <p className="mt-4 text-gray-500">
            <span className="text-black">
              リクエストされた URL はこのサーバーで見つかりませんでした。
            </span>
            確認できたことは以上です。
          </p>
        </section>
        <div className="relative h-48 w-48">
          <Image src="/images/404.png" fill alt="Logo" sizes="50vw" />
        </div>
      </div>
    </main>
  );
}

export default NotFoundPage;
