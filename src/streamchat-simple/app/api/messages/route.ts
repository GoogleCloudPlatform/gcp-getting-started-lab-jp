import { getFirestore } from "firebase-admin/firestore";
import firebaseAdminApp from "@/app/libs/firebase/admin";

import { NextResponse } from "next/server";
import { getAuth } from "firebase-admin/auth";
import { postMessage } from "@/app/libs/firebase/message";

export async function POST(request: Request) {
  const headerToken = request.headers.get("Authorization");
  if (!headerToken) {
    return NextResponse.json(
      { message: "Bearer token must be provided" },
      { status: 401 }
    );
  }
  const headerParts = headerToken.split(" ");
  if (
    headerParts.length < 2 ||
    headerParts[0] !== "Bearer" ||
    !headerParts[1]
  ) {
    return NextResponse.json({ message: "Invalid token" }, { status: 401 });
  }

  const token = headerParts[1];
  const { message } = await request.json();

  try {
    const { uid } = await getAuth(firebaseAdminApp).verifyIdToken(token);
    const user = await getAuth(firebaseAdminApp).getUser(uid);
    const doc = await getFirestore(firebaseAdminApp)
      .collection("users")
      .doc(uid)
      .get();
    await postMessage({
      name: user.displayName ? user.displayName : "",
      text: message,
      animal: doc.get("animal"),
      color: doc.get("color"),
    });
    return NextResponse.json({ message: "posted a message" }, { status: 200 });
  } catch (e) {
    console.error(e);
    return NextResponse.json(
      { message: "failed to post a message" },
      { status: 500 }
    );
  }
}
