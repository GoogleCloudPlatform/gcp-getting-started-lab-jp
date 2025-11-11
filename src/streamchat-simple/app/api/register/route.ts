import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import firebaseAdminApp from "@/app/libs/firebase/admin";
import { NextResponse } from "next/server";
import { getRandomAnimal } from "@/app/libs/avatar/animal";
import { getRandomColor } from "@/app/libs/avatar/color";

export async function POST(request: Request) {
  const { name, email, password } = await request.json();
  try {
    const { uid } = await getAuth(firebaseAdminApp).createUser({
      email: email,
      displayName: name,
      password: password,
    });
    await getFirestore(firebaseAdminApp).collection("users").doc(uid).set({
      animal: getRandomAnimal(),
      color: getRandomColor(),
    });
  } catch (e) {
    console.error(e);
    return NextResponse.json({ message: e }, { status: 500 });
  }
  return NextResponse.json({ message: "success" });
}
