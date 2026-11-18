"""SQLite kalıcılığı: hikayeler, promptlar, maliyetler, video durumları ve adım çalıştırmaları."""
from __future__ import annotations

import json
import sqlite3
import threading
import time
from pathlib import Path
from typing import Any

from .config import settings

_SCHEMA = """
CREATE TABLE IF NOT EXISTS jobs (
    id TEXT PRIMARY KEY,
    topic TEXT,
    title TEXT,
    status TEXT NOT NULL,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    mock INTEGER NOT NULL DEFAULT 1,
    cost_usd REAL NOT NULL DEFAULT 0,
    video_path TEXT,
    youtube_video_id TEXT,
    error TEXT,
    state_json TEXT
);
CREATE TABLE IF NOT EXISTS step_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id TEXT NOT NULL,
    agent TEXT NOT NULL,
    status TEXT NOT NULL,          -- success | fail
    started_at REAL NOT NULL,
    ended_at REAL,
    cost_usd REAL NOT NULL DEFAULT 0,
    note TEXT
);
CREATE INDEX IF NOT EXISTS idx_step_runs_job ON step_runs(job_id);
"""

_lock = threading.Lock()


def _connect() -> sqlite3.Connection:
    settings.ensure_dirs()
    conn = sqlite3.connect(str(settings.db_path), check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


_conn: sqlite3.Connection | None = None


def conn() -> sqlite3.Connection:
    global _conn
    if _conn is None:
        _conn = _connect()
        _conn.executescript(_SCHEMA)
        _conn.commit()
    return _conn


def init_db() -> None:
    c = conn()
    with _lock:
        # Sunucu yeniden başladıysa yarım kalan işleri işaretle.
        c.execute(
            "UPDATE jobs SET status='interrupted', error='Sunucu yeniden başlatıldı; iş yarıda kaldı.', updated_at=? "
            "WHERE status IN ('queued','running','uploading')",
            (time.time(),),
        )
        c.commit()


def _dumps(obj: Any) -> str:
    return json.dumps(obj, ensure_ascii=False, default=str)


def create_job(job_id: str, topic: str | None, mock: bool, state: dict) -> None:
    now = time.time()
    with _lock:
        conn().execute(
            "INSERT INTO jobs(id, topic, title, status, created_at, updated_at, mock, state_json) "
            "VALUES(?,?,?,?,?,?,?,?)",
            (job_id, topic, None, "queued", now, now, int(mock), _dumps(state)),
        )
        conn().commit()


def update_job(job_id: str, **fields: Any) -> None:
    if not fields:
        return
    if "state" in fields:
        fields["state_json"] = _dumps(fields.pop("state"))
    fields["updated_at"] = time.time()
    cols = ", ".join(f"{k}=?" for k in fields)
    with _lock:
        conn().execute(f"UPDATE jobs SET {cols} WHERE id=?", (*fields.values(), job_id))
        conn().commit()


def get_job(job_id: str) -> dict | None:
    with _lock:
        row = conn().execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone()
    return _row_to_job(row) if row else None


def list_jobs(limit: int = 30) -> list[dict]:
    with _lock:
        rows = conn().execute("SELECT * FROM jobs ORDER BY created_at DESC LIMIT ?", (limit,)).fetchall()
    return [_row_to_job(r) for r in rows]


def _row_to_job(row: sqlite3.Row) -> dict:
    d = dict(row)
    raw = d.pop("state_json", None)
    d["state"] = json.loads(raw) if raw else {}
    d["mock"] = bool(d.get("mock"))
    return d


def start_step(job_id: str, agent: str) -> int:
    with _lock:
        cur = conn().execute(
            "INSERT INTO step_runs(job_id, agent, status, started_at) VALUES(?,?,?,?)",
            (job_id, agent, "running", time.time()),
        )
        conn().commit()
        return int(cur.lastrowid)


def finish_step(step_id: int, ok: bool, cost: float = 0.0, note: str | None = None) -> None:
    with _lock:
        conn().execute(
            "UPDATE step_runs SET status=?, ended_at=?, cost_usd=?, note=? WHERE id=?",
            ("success" if ok else "fail", time.time(), cost, note, step_id),
        )
        conn().commit()


def stats() -> dict:
    with _lock:
        c = conn()
        jobs_total = c.execute("SELECT COUNT(*) FROM jobs").fetchone()[0]
        videos = c.execute("SELECT COUNT(*) FROM jobs WHERE video_path IS NOT NULL").fetchone()[0]
        by_status = {r[0]: r[1] for r in c.execute("SELECT status, COUNT(*) FROM jobs GROUP BY status")}
        cost_total = c.execute("SELECT COALESCE(SUM(cost_usd),0) FROM jobs").fetchone()[0]
        steps = c.execute(
            "SELECT agent, SUM(status='success'), SUM(status='fail'), COALESCE(SUM(cost_usd),0), "
            "AVG(CASE WHEN ended_at IS NOT NULL THEN ended_at-started_at END) "
            "FROM step_runs GROUP BY agent"
        ).fetchall()
    step_stats = {}
    for agent, ok, fail, cost, avg_s in steps:
        ok, fail = int(ok or 0), int(fail or 0)
        total = ok + fail
        step_stats[agent] = {
            "success": ok,
            "fail": fail,
            "rate": round(ok / total, 3) if total else None,
            "cost_usd": round(float(cost or 0), 4),
            "avg_seconds": round(float(avg_s), 2) if avg_s else None,
        }
    return {
        "jobs_total": jobs_total,
        "videos_rendered": videos,
        "approved": by_status.get("approved", 0) + by_status.get("uploaded", 0),
        "uploaded": by_status.get("uploaded", 0),
        "failed": by_status.get("failed", 0),
        "awaiting_approval": by_status.get("awaiting_approval", 0),
        "by_status": by_status,
        "cost_total_usd": round(float(cost_total or 0), 4),
        "cost_per_video_usd": round(float(cost_total or 0) / videos, 4) if videos else 0.0,
        "steps": step_stats,
    }


def db_file() -> Path:
    return settings.db_path
