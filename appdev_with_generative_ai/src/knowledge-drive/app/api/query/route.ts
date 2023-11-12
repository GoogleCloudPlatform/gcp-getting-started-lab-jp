import { NextResponse } from "next/server";
import { GoogleAuth } from "google-auth-library";

// Access local API when SEARCH_HOST is not set.
const URL = process.env.SEARCH_HOST || "http://localhost:3000/api";
const ENDPOINT_PATH = "/search";

const removeExtensionFromFileId = (fileId: string): string => {
  if (fileId.includes(".")) {
    return fileId.split(".")[0];
  }
  return fileId;
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

export async function POST(request: Request) {
  const { userId, question } = await request.json();
  try {
    let status, data;
    if (process.env.SEARCH_HOST) {
      const auth = new GoogleAuth();
      const client = await auth.getIdTokenClient(process.env.SEARCH_HOST);
      const res = await client.request({
        url: `${URL}${ENDPOINT_PATH}`,
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        data: {
          user_id: userId,
          question: question,
        },
      });
      status = res.status;
      data = res.data;
    } else {
      const result = await fetch(`${URL}${ENDPOINT_PATH}`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          question: question,
        }),
      });
      status = result.status;
      data = await result.json();
    }
    if (status !== 200) {
      return NextResponse.json({ message: "Search failed" }, { status: 500 });
    }
    if (!isValidSearchResponse(data)) {
      return NextResponse.json(
        { message: "Invalid response from search API" },
        { status: 500 }
      );
    }
    console.log(data);

    return NextResponse.json({
      answer: data.answer,
      metadata: {
        source: removeExtensionFromFileId(data.metadata.source),
        page: data.metadata.page,
      },
    });
  } catch (e) {
    console.error(e);
    return NextResponse.json({ message: e }, { status: 500 });
  }
}
