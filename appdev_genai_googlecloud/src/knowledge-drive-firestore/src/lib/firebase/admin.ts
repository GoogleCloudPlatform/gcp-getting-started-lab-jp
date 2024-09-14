import "server-only";

import {
  initializeApp,
  applicationDefault,
  AppOptions,
  getApp,
  App,
} from "firebase-admin/app";

const ADMIN = "ADMIN";
const firebaseAdminConfig: AppOptions = {
  credential: applicationDefault(),
};

const initialize = () => {
  let adminApp: App;
  try {
    adminApp = getApp(ADMIN);
  } catch (e) {
    adminApp = initializeApp(firebaseAdminConfig, ADMIN);
  }
  return adminApp;
};

const firebaseAdminApp = initialize();

export default firebaseAdminApp;
