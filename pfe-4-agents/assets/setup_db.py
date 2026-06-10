import os

import sqlalchemy
from google.cloud.sql.connector import Connector

PROJECT_ID = os.environ["PROJECT_ID"]
REGION = os.environ["REGION"]
DB_INSTANCE = os.environ["DB_INSTANCE"]
DB_NAME = os.environ["DB_NAME"]
DB_USER = os.environ["DB_USER"]
DB_PASS = os.environ["DB_PASS"]

INSTANCE_CONNECTION_NAME = f"{PROJECT_ID}:{REGION}:{DB_INSTANCE}"

CREATE_SYSTEM_STATUS_TABLE = """
CREATE TABLE IF NOT EXISTS system_status (
  service_name VARCHAR(255) PRIMARY KEY,
  status VARCHAR(255) NOT NULL,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
"""

UPSERT_SYSTEM_STATUS = """
INSERT INTO system_status(service_name, status)
VALUES
  ('経費精算システム', '障害発生中。復旧見込みは 15:00 です。'),
  ('勤怠管理システム', '正常稼働中です。'),
  ('社内ポータル', '一部ユーザーでログイン遅延が発生しています。')
ON CONFLICT (service_name) DO UPDATE
SET status = EXCLUDED.status,
    updated_at = CURRENT_TIMESTAMP
"""

CREATE_EMPLOYEES_TABLE = """
CREATE TABLE IF NOT EXISTS employees (
  name VARCHAR(255) PRIMARY KEY,
  department VARCHAR(255) NOT NULL,
  email VARCHAR(255) NOT NULL,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
"""

UPSERT_EMPLOYEES = """
INSERT INTO employees(name, department, email)
VALUES
  ('佐藤花子', 'ITシステム部', 'sato@example.com'),
  ('田中太郎', '経理部', 'tanaka@example.com'),
  ('鈴木一郎', '人事部', 'suzuki@example.com')
ON CONFLICT (name) DO UPDATE
SET department = EXCLUDED.department,
    email = EXCLUDED.email,
    updated_at = CURRENT_TIMESTAMP
"""

connector = Connector()


def getconn():
    return connector.connect(
        INSTANCE_CONNECTION_NAME,
        "pg8000",
        user=DB_USER,
        password=DB_PASS,
        db=DB_NAME,
    )


pool = sqlalchemy.create_engine(
    "postgresql+pg8000://",
    creator=getconn,
    pool_pre_ping=True,
)

db_conn = pool.connect()
db_conn.execute(sqlalchemy.text(CREATE_SYSTEM_STATUS_TABLE))
db_conn.execute(sqlalchemy.text(UPSERT_SYSTEM_STATUS))
db_conn.execute(sqlalchemy.text(CREATE_EMPLOYEES_TABLE))
db_conn.execute(sqlalchemy.text(UPSERT_EMPLOYEES))
db_conn.commit()
db_conn.close()

connector.close()

print("Cloud SQL への初期データ投入が完了しました。")
