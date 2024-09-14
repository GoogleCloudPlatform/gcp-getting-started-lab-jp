import { useQuery } from "@tanstack/react-query";
import Image from "next/image";
import RingLoader from "react-spinners/RingLoader";

type LLMSearchResultProps = {
  question: string;
};

export type QuestionResponse = {
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

const QUERY_API_PATH = "/api/question";

const LLMSearchResult = ({ question }: LLMSearchResultProps) => {
  const llmSearch = async (question: string) => {
    const res = await fetch(QUERY_API_PATH, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ question: question }),
    });
    if (!res.ok) {
      throw new Error("Failed to execute LLM search");
    }
    const data = await res.json();
    if (!isValidSearchResponse(data)) {
      throw new Error("Invalid search response");
    }
    return data;
  };

  const {
    isFetching,
    data: result,
    error,
  } = useQuery({
    queryKey: ["llm-search", question],
    queryFn: () => llmSearch(question),
    retry: false,
  });

  if (isFetching) {
    return (
      <div className="flex h-full w-full items-center justify-center">
        <RingLoader size={120} color="purple" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex h-full w-full flex-col items-center justify-center">
        <div className="flex flex-col items-center justify-center">
          <Image src="/images/error.png" width={80} height={80} alt="error" />
          <h1 className="mt-4 text-xl text-red-500">エラーが発生しました</h1>
        </div>
      </div>
    );
  }

  return (
    <div className="flex h-full w-full flex-col">
      <label htmlFor="question" className="text-lg">
        質問
      </label>
      <div
        id="question"
        className="mt-2 h-20 overflow-y-scroll rounded-md bg-white p-2 shadow"
      >
        {question}
      </div>
      <label htmlFor="answer" className="mt-6 text-lg">
        回答
      </label>
      <div
        id="answer"
        className="mt-2 h-40 overflow-y-scroll rounded-md bg-white p-2 shadow"
      >
        {result?.answer}
      </div>
      <label htmlFor="source" className="mt-6 text-lg">
        回答が記載されているファイル / ページ番号
      </label>
      <div id="source" className="mt-2 flex h-8">
        <div className="flex h-full w-[490px] items-center overflow-x-scroll rounded-md bg-white p-2 shadow">
          {result.metadata.source}
        </div>
        <div className="grow" />
        <div className="flex w-10 items-center justify-center rounded-md bg-white p-2 shadow">
          {result?.metadata.page == null
            ? ""
            : (result.metadata.page + 1).toString()}
        </div>
      </div>
    </div>
  );
};

export default LLMSearchResult;
