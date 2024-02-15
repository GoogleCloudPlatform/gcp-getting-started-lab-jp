import { NextResponse } from "next/server";
import { GoogleAuth } from "google-auth-library";
import { QuestionResponse } from "@/components/llm-search-result";
import { getOwner, getSourceIP } from "@/lib/actions";
import { headers } from "next/headers";
import { logError, logInfo } from "@/lib/logging";

const ENDPOINT_PATH = "/search";

const isValidSearchResponse = (res: any) =>
  "answer" in res &&
  typeof res.answer === "string" &&
  "metadata" in res &&
  typeof res.metadata === "object" &&
  "source" in res.metadata &&
  typeof res.metadata.source === "string" &&
  "page" in res.metadata &&
  typeof res.metadata.page === "number";

export async function POST(request: Request) {
  const action = "question";
  const headersList = headers();
  const owner = getOwner(headersList);
  const sourceIP = getSourceIP(headersList);
  const { question } = await request.json();

  if (!process.env.SEARCH_HOST) {
    logError({
      owner: owner,
      sourceIP: sourceIP,
      action: action,
      message: `${sourceIP}/${owner}/${action}: No search host set`,
    });
    return NextResponse.json(
      { message: "No search host set" },
      { status: 500 },
    );
  }

  try {
    const auth = new GoogleAuth();
    const client = await auth.getIdTokenClient(process.env.SEARCH_HOST);
    const res = await client.request({
      url: `${process.env.SEARCH_HOST}${ENDPOINT_PATH}`,
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      data: {
        user_id: owner,
        question: question,
      },
    });
    const status = res.status;
    const data = res.data;
    if (status !== 200) {
      logError({
        owner: owner,
        sourceIP: sourceIP,
        action: action,
        message: `${sourceIP}/${owner}/${action}/${question}: Got ${status} from search backend API`,
      });
      return NextResponse.json({ message: "Search failed" }, { status: 500 });
    }
    if (!isValidSearchResponse(data)) {
      logError({
        owner: owner,
        sourceIP: sourceIP,
        action: action,
        message: `${sourceIP}/${owner}/${action}/${question}: Invalid response from search backend API`,
        data: data,
      });
      return NextResponse.json(
        { message: "Invalid response from search API" },
        { status: 500 },
      );
    }
    const validData = data as QuestionResponse;

    // validData.metadata.source = "[UUID:21 characters].[Filename]"
    const filename = validData.metadata.source.substring(22);

    logInfo({
      owner: owner,
      sourceIP: sourceIP,
      action: action,
      message: `${sourceIP}/${owner}/${action}/${question}: Answered to the question`,
      data: validData,
    });
    return NextResponse.json({
      answer: validData.answer,
      metadata: {
        source: filename,
        page: validData.metadata.page,
      },
    });
  } catch (e) {
    logError({
      owner: owner,
      sourceIP: sourceIP,
      action: action,
      message: `${sourceIP}/${owner}/${action}/${question}: Unknown error occurred`,
      error: e,
    });
    return NextResponse.json({ message: e }, { status: 500 });
  }
}
