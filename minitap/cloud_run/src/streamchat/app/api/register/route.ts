import bcrypt from "bcrypt";
import { addUser } from "@/app/libs/firebase/user";

import { NextResponse } from "next/server";

export async function POST(request: Request) {
  const { email, name, password } = await request.json();

  const hashedPassword = await bcrypt.hash(password, 12);

  const user = await addUser(name, email, hashedPassword);

  return NextResponse.json(user);
}
