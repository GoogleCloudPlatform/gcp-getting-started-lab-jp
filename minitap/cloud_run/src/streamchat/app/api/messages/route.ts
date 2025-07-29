import { getServerSession } from "next-auth";
import { authOptions } from "../auth/[...nextauth]/route";
import { NextResponse } from "next/server";
import { saveMessage } from "@/app/libs/firebase/message";

export async function POST(request: Request) {
  const { message } = await request.json();
  const session = await getServerSession(authOptions);
  if (!session || !session.user?.name) {
    return NextResponse.json(
      { message: "You must be logged in." },
      { status: 401 }
    );
  }
  try {
    await saveMessage(
      session.user.name,
      message,
      session.user.image ? session.user.image : ""
    );
  } catch (error) {
    return NextResponse.json({ message: error }, { status: 500 });
  }
  return NextResponse.json({ message: "success" });
}
