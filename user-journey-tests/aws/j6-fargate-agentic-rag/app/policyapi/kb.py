"""Knowledge-base access: PostgreSQL full-text search over policy sections.

Retrieval is lexical, not vector-based: a generated `tsvector` column with a
GIN index answers `websearch_to_tsquery` searches ranked by `ts_rank_cd`, and
a `pg_trgm` similarity pass catches misspelled or fragmentary queries that
full-text search misses. Both are deterministic, which keeps the pipeline
answer mode byte-stable and needs no embedding model anywhere.

A lazily-opened psycopg connection pool is shared across requests; the
credentials JSON comes from Secrets Manager once per process.
"""

from __future__ import annotations

from typing import Any, Optional

from psycopg.conninfo import make_conninfo
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from .clients import secret_payload
from .config import CFG

_pool: Optional[ConnectionPool] = None


def _conninfo() -> str:
    creds: dict[str, Any] = {}
    if CFG.kb_secret_arn:
        creds = secret_payload(CFG.kb_secret_arn)
    # make_conninfo quotes every value — passwords with spaces/quotes and
    # empty strings survive, which a hand-built "k=v k=v" string does not.
    return make_conninfo(
        host=creds.get("host") or CFG.kb_host,
        port=int(creds.get("port") or 5432),
        user=creds.get("user") or "copilot",
        password=creds.get("password") or "",
        dbname=creds.get("dbname") or CFG.kb_database,
        connect_timeout=5,
    )


def pool() -> ConnectionPool:
    global _pool
    if _pool is None:
        _pool = ConnectionPool(
            _conninfo(), min_size=0, max_size=4, open=True, kwargs={"row_factory": dict_row}
        )
    return _pool


def healthcheck() -> None:
    with pool().connection() as conn:
        conn.execute("SELECT 1")


def fulltext_search(query: str, topic: str, limit: int = 5) -> list[dict[str, Any]]:
    """Ranked full-text hits; empty topic searches every topic."""
    sql = """
        SELECT d.ref, d.title, d.topic, s.position, s.heading,
               left(s.body, 260) AS excerpt,
               ts_rank_cd(s.search, websearch_to_tsquery('english', %(q)s)) AS rank
        FROM sections s
        JOIN documents d ON d.ref = s.doc_ref
        WHERE s.search @@ websearch_to_tsquery('english', %(q)s)
          AND (%(topic)s = '' OR d.topic = %(topic)s)
        ORDER BY rank DESC, d.ref, s.position
        LIMIT %(limit)s
    """
    with pool().connection() as conn:
        return conn.execute(sql, {"q": query, "topic": topic, "limit": limit}).fetchall()


def fuzzy_search(query: str, limit: int = 5) -> list[dict[str, Any]]:
    """Trigram-similarity fallback for queries full-text search whiffs on."""
    sql = """
        SELECT d.ref, d.title, d.topic, s.position, s.heading,
               left(s.body, 260) AS excerpt,
               similarity(s.heading || ' ' || s.body, %(q)s) AS rank
        FROM sections s
        JOIN documents d ON d.ref = s.doc_ref
        WHERE similarity(s.heading || ' ' || s.body, %(q)s) > 0.05
        ORDER BY rank DESC, d.ref, s.position
        LIMIT %(limit)s
    """
    with pool().connection() as conn:
        return conn.execute(sql, {"q": query, "limit": limit}).fetchall()


def document(ref: str) -> Optional[dict[str, Any]]:
    with pool().connection() as conn:
        doc = conn.execute(
            "SELECT ref, title, topic, owner_team, effective_from FROM documents WHERE ref = %s",
            (ref.strip().upper(),),
        ).fetchone()
        if doc is None:
            return None
        doc["sections"] = conn.execute(
            "SELECT position, heading, body FROM sections WHERE doc_ref = %s ORDER BY position",
            (doc["ref"],),
        ).fetchall()
        return doc


def topics() -> list[dict[str, Any]]:
    with pool().connection() as conn:
        return conn.execute(
            "SELECT topic, count(*) AS documents FROM documents GROUP BY topic ORDER BY topic"
        ).fetchall()
