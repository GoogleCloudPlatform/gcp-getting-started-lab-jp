import {
  signInWithEmailAndPassword,
  getAuth,
  UserCredential,
} from "firebase/auth";
import firebaseClientApp from "./client";
import { FirebaseError } from "firebase/app";
import { signUpApi } from "../api/auth";

const auth = getAuth(firebaseClientApp);

export const signIn = async ({
  email,
  password,
}: SignInRequest): Promise<UserCredential> => {
  try {
    const user = await signInWithEmailAndPassword(auth, email, password);
    return user;
  } catch (e) {
    if (e instanceof FirebaseError) {
      console.error(e.code);
      throw e;
    }
    throw e;
  }
};

export const signUp = async (
  request: SignUpRequest,
  csrfToken: string
): Promise<UserCredential> => {
  try {
    await signUpApi(request, csrfToken);
    const user = await signInWithEmailAndPassword(
      auth,
      request.email,
      request.password
    );
    return user;
  } catch (e) {
    if (e instanceof FirebaseError) {
      console.error(e.code);
      throw e;
    }
    throw e;
  }
};
