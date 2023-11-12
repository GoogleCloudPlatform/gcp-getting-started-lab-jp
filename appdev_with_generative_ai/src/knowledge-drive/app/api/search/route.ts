import { NextResponse } from "next/server";

export async function POST(request: Request) {
  return NextResponse.json({
    answer:
      "(テスト返答)今日は良い天気ですね。今日のような日は外に出るのが良いでしょう",
    metadata: {
      source: "UiXQ7c9jYP2lCbFMwShS",
      page: 5,
    },
  });
}
