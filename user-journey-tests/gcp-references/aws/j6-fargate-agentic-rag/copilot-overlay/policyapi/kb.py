"""Knowledge-base access — the migration's only data-layer diff.

Identical retrieval to the journey (Postgres full-text + trigram over the
same schema; Cloud SQL runs it unchanged). What changed is credential
delivery: on AWS the service fetched a Secrets Manager JSON via boto3; here
`agents-cli deploy --secrets KB_CONNECTION_JSON=<secret>` has Agent Runtime
inject the Secret Manager payload straight into the environment, so there is
no secrets client in the code at all.
"""

from __future__ import annotations

import json
import os
from typing import Any, Optional

from psycopg.conninfo import make_conninfo
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

_pool: Optional[ConnectionPool] = None


def _conninfo() -> str:
    creds = json.loads(os.environ.get("KB_CONNECTION_JSON", "{}"))
    return make_conninfo(
        host=creds.get("host", ""),
        port=int(creds.get("port", 5432)),
        user=creds.get("user", "copilot"),
        password=creds.get("password", ""),
        dbname=creds.get("dbname", "policykb"),
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
