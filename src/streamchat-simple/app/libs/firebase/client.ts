import {
  initializeApp,
  FirebaseOptions,
  getApp,
  FirebaseApp,
} from "firebase/app";

const CLIENT = "CLIENT";

const firebaseClientConfig: FirebaseOptions = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
  storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_ID,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
};

const initialize = () => {
  let clientApp: FirebaseApp;
  try {
    clientApp = getApp(CLIENT);
  } catch (e) {
    clientApp = initializeApp(firebaseClientConfig, CLIENT);
  }
  return clientApp;
};

const firebaseClientApp = initialize();

export default firebaseClientApp;
