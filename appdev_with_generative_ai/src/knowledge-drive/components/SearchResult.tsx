import { useEffect, useState } from "react";
import RingLoader from "react-spinners/RingLoader";
import SourceFile from "./SourceFile";
import { User } from "firebase/auth";
import Image from "next/image";

type SearchResultProps = {
  query: string;
  csrfToken: string;
  user: User;
};

type QueryResponse = {
  answer: string;
  metadata: {
    page: number;
    source: string;
  };
};

const isValidSearchResponse = (res: any) =>
  "answer" in res &&
  typeof res.answer === "string" &&
  "metadata" in res &&
  typeof res.metadata === "object" &&
  "source" in res.metadata &&
  typeof res.metadata.source === "string" &&
  "page" in res.metadata &&
  typeof res.metadata.page === "number";

const QUERY_API_PATH = "/api/query";

const SearchResult = ({ user, query, csrfToken }: SearchResultProps) => {
  const [response, setResponse] = useState<QueryResponse | null>(null);
  const [isLoading, setIsloading] = useState(false);
  const [isError, setIsError] = useState(false);
  useEffect(() => {
    const search = async () => {
      setIsloading(true);
      setIsError(false);
      try {
        const result = await fetch(QUERY_API_PATH, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": csrfToken,
          },
          body: JSON.stringify({ userId: user.uid, question: query }),
        });
        if (!result.ok) {
          console.log(result.json());
          setIsError(true);
          return;
        }
        const resultJson = await result.json();
        if (!isValidSearchResponse(resultJson)) {
          setIsError(true);
          return;
        }
        setResponse(resultJson);
      } catch (e) {
        setIsError(true);
        console.log(e);
      } finally {
        setIsloading(false);
      }
    };
    search();
  }, [user, query, csrfToken]);

  if (isLoading) {
    return (
      <div className="w-full h-full flex items-center justify-center">
        <RingLoader size={120} color="purple" />
      </div>
    );
  }

  if (isError) {
    return (
      <div className="h-full w-full flex flex-col items-center justify-center">
        <div className="flex flex-col items-center justify-center">
          <Image src="/images/error.png" width={80} height={80} alt="error" />
          <h1 className="text-red-500 mt-4 text-xl">エラーが発生しました</h1>
        </div>
      </div>
    );
  }

  return (
    <div className="h-full w-full flex flex-col">
      <label htmlFor="question" className="text-lg">
        質問
      </label>
      <div
        id="question"
        className="bg-white h-20 overflow-y-scroll shadow mt-2 p-2 rounded-md"
      >
        {query}
      </div>
      <label htmlFor="answer" className="text-lg mt-6">
        回答
      </label>
      <div
        id="answer"
        className="bg-white h-40 shadow mt-2 p-2 rounded-md overflow-y-scroll"
      >
        {response?.answer}
      </div>
      <label htmlFor="source" className="text-lg mt-6">
        回答が記載されているファイル / ページ番号
      </label>
      <div id="source" className="h-8 mt-2 flex">
        <div className="flex w-[490px] items-center overflow-x-scroll shadow rounded-md h-full bg-white p-2">
          {!response?.metadata.source ? (
            ""
          ) : (
            <SourceFile user={user} fileId={response.metadata.source} />
          )}
        </div>
        <div className="grow" />
        <div className="flex items-center justify-center w-10 p-2 shadow rounded-md bg-white">
          {response?.metadata.page == null
            ? ""
            : (response.metadata.page + 1).toString()}
        </div>
      </div>
    </div>
  );
};

export default SearchResult;
