import pg from "pg";
import { Connector, IpAddressTypes } from "@google-cloud/cloud-sql-connector";
const { Pool } = pg;

declare global {
  var db: {
    pool: pg.Pool | null;
  };
}

if (!global.db) {
  global.db = { pool: null };
}

export const createPoolWithConnector = async () => {
  try {
    if (!global.db.pool) {
      const connector = new Connector();
      const clientOpts = await connector.getOptions({
        instanceConnectionName: process.env.INSTANCE_CONNECTION_NAME || "",
        ipType: IpAddressTypes.PUBLIC,
      });

      global.db.pool = new Pool({
        ...clientOpts,
        user: process.env.DB_USER,
        password: process.env.DB_PASSWORD,
        database: process.env.DB_NAME,
        max: 5,
      });
    }
  } catch (error) {
    console.error(`Database connection failed: ${error}`);
    throw new Error("Database connection failed");
  }
  return global.db.pool;
};
