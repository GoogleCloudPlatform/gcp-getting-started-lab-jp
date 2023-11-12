import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import firebaseAdminApp from "@/lib/firebase/admin";
import { NextResponse } from "next/server";

const firestore = getFirestore(firebaseAdminApp);

const ROOT_FOLDER_ID = "ROOT_FOLDER";
const ROOT_FOLDER_NAME = "ルートフォルダ";

export async function POST(request: Request) {
  const { name, email, password } = await request.json();
  try {
    const { uid } = await getAuth(firebaseAdminApp).createUser({
      email: email,
      displayName: name,
      password: password,
    });
    const batch = firestore.batch();
    const userRef = firestore.collection("users").doc(uid);
    batch.set(userRef, { timestamp: FieldValue.serverTimestamp() });
    const itemsRef = firestore
      .collection("users")
      .doc(uid)
      .collection("items")
      .doc(ROOT_FOLDER_ID);
    batch.create(itemsRef, {
      name: ROOT_FOLDER_NAME,
      timestamp: FieldValue.serverTimestamp(),
      parent: null,
      isFolder: true,
      filesize: 0,
    });
    await batch.commit();
  } catch (e) {
    console.error(e);
    return NextResponse.json({ message: e }, { status: 500 });
  }
  return NextResponse.json({ message: "success" });
}
