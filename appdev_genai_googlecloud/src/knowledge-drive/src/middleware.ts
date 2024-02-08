import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { MY_DRIVE_URL } from "./lib/constants";

export const middleware = (request: NextRequest) => {
  return NextResponse.redirect(new URL(MY_DRIVE_URL, request.url));
};

export const config = {
  matcher: "/",
};
