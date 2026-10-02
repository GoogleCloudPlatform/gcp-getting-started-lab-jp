"""db.py — catalog persistence for the online shop (psycopg 3).

Host/port/dbname come from /etc/shop.env; the credentials JSON is fetched
from Secrets Manager through the aws_clients funnel exactly once per process.
bootstrap() applies schema.sql and the deterministic 12-book seed at startup
(idempotent: CREATE TABLE IF NOT EXISTS + ON CONFLICT DO NOTHING), so a fresh
instance converges on its own and re-seeding never duplicates rows.
"""

import os
import pathlib
import threading

import psycopg
from psycopg.rows import dict_row

import aws_clients as cloud

_SCHEMA_PATH = pathlib.Path(__file__).resolve().parent / "schema.sql"

_creds_lock = threading.Lock()
_creds = None
_bootstrapped = False

# The deterministic seed: same 12 rows on every instance, every deploy —
# parity checks can hash the catalog. (id, title, author, price_yen,
# published_year, condition_grade, added_on)
SEED_BOOKS = [
    (1, "Kokoro", "Natsume Soseki", 480, 1914, "B", "2016-04-02"),
    (2, "Botchan", "Natsume Soseki", 350, 1906, "C", "2016-04-02"),
    (3, "I Am a Cat", "Natsume Soseki", 620, 1905, "B", "2016-05-19"),
    (4, "Rashomon and Seventeen Other Stories", "Ryunosuke Akutagawa", 540, 1915, "A", "2017-01-08"),
    (5, "Snow Country", "Yasunari Kawabata", 700, 1937, "B", "2017-06-30"),
    (6, "The Makioka Sisters", "Junichiro Tanizaki", 880, 1943, "C", "2018-02-14"),
    (7, "The Tale of Genji (Vol. 1)", "Murasaki Shikibu", 1200, 1008, "C", "2018-11-03"),
    (8, "Musashi", "Eiji Yoshikawa", 950, 1935, "B", "2019-07-21"),
    (9, "Silence", "Shusaku Endo", 610, 1966, "A", "2020-03-15"),
    (10, "The Woman in the Dunes", "Kobo Abe", 660, 1962, "B", "2021-09-09"),
    (11, "Kitchen", "Banana Yoshimoto", 430, 1988, "A", "2023-05-27"),
    (12, "Norwegian Wood", "Haruki Murakami", 520, 1987, "B", "2024-10-12"),
]

_INSERT_SQL = """
INSERT INTO books (id, title, author, price_yen, published_year, condition_grade, added_on)
VALUES (%s, %s, %s, %s, %s, %s, %s)
ON CONFLICT (id) DO NOTHING
"""


def _credentials():
    """Secrets Manager round-trip once per process, cached afterwards."""
    global _creds
    with _creds_lock:
        if _creds is None:
            secret = cloud.get_secret_json(os.environ["SECRET_ID_DB"])
            _creds = {
                "user": secret.get("username", "shop"),
                "password": secret["password"],
            }
    return dict(_creds)


def connect():
    creds = _credentials()
    return psycopg.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "5432")),
        dbname=os.environ.get("DB_NAME", "online_shop"),
        user=creds["user"],
        password=creds["password"],
        connect_timeout=5,
        row_factory=dict_row,
    )


def bootstrap():
    """Schema + seed. Safe to run from every worker on every boot."""
    global _bootstrapped
    if _bootstrapped:
        return
    schema_sql = _SCHEMA_PATH.read_text()
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute(schema_sql)
            cur.executemany(_INSERT_SQL, SEED_BOOKS)
    _bootstrapped = True


def list_books():
    bootstrap()
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM books ORDER BY id")
            return cur.fetchall()


def get_book(book_id):
    bootstrap()
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM books WHERE id = %s", (book_id,))
            return cur.fetchone()


def ping():
    """SELECT 1 — the /health dependency check."""
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
            cur.fetchone()
    return True


def server_version():
    """SELECT version() — the /admin/aws-check DB ping."""
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT version()")
            return cur.fetchone()["version"]
