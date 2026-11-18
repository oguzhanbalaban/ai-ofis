"""1. Director Agent (Yönetmen): konuyu belirler, akışı yönetir, hata/QA/revizyon durumunda
ilgili adımı yeniden tetikler. LangGraph'ta yönlendirici (router) düğümdür."""
from __future__ import annotations

from .. import db
from ..config import settings
from ..events import bus
from ..mock_data import daily_topic
from .registry import AGENT_BY_ID, PIPELINE_STEPS


def _reset_downstream(step_status: dict, target: str) -> dict:
    out = dict(step_status)
    start = PIPELINE_STEPS.index(target)
    for s in PIPELINE_STEPS[start:]:
        out[s] = "pending"
    return out


async def director_node(state: dict) -> dict:
    from ..jobs import persist_state

    job_id = state["job_id"]
    retries = dict(state.get("retries") or {})
    step_status = dict(state.get("step_status") or {s: "pending" for s in PIPELINE_STEPS})
    history = list(state.get("history") or [])
    out: dict = {}
    step_id = db.start_step(job_id, "director")

    async def say(text: str) -> None:
        await bus.agent("director", "WORKING", text, job_id)

    failed = state.get("failed_step")
    qa_fb = state.get("qa_feedback")
    revision = state.get("revision") or {}

    if failed:
        retries[failed] = retries.get(failed, 0) + 1
        role = AGENT_BY_ID[failed]["role"]
        if retries[failed] <= settings.max_step_retries:
            route = failed
            await say(f"{role} yeniden tetikleniyor ({retries[failed]}. tekrar)")
            await bus.log(
                f"Hata algılandı: {state.get('error')}. {role} adımı yeniden tetikleniyor "
                f"(tekrar {retries[failed]}/{settings.max_step_retries}).",
                agent="director", level="warn", job_id=job_id,
            )
        else:
            route = "fail"
            await say("Üretim durduruldu: tekrar sınırı aşıldı")
            await bus.log(f"{role} {settings.max_step_retries} tekrardan sonra da başarısız. Üretim durduruldu.",
                          agent="director", level="error", job_id=job_id)
        out.update(retries=retries, failed_step=None)
    elif qa_fb:
        rounds = int(state.get("qa_rounds") or 0) + 1
        target = qa_fb.get("target", "editor")
        if rounds <= settings.max_qa_rounds:
            route = target
            await say(f"QA geri bildirimi → {AGENT_BY_ID[target]['role']}")
            await bus.log(f"QA reddetti ({'; '.join(qa_fb.get('reasons', []))}). "
                          f"{AGENT_BY_ID[target]['role']} adımına geri gönderiliyor (tur {rounds}).",
                          agent="director", level="warn", data=qa_fb, job_id=job_id)
            out["fix_request"] = {"target": target, "reasons": qa_fb.get("reasons", []), "source": "qa"}
            step_status = _reset_downstream(step_status, target)
        else:
            route = "fail"
            await bus.log("QA tur sınırı aşıldı; üretim durduruldu.", agent="director", level="error", job_id=job_id)
        out.update(qa_rounds=rounds, qa_feedback=None)
    elif revision.get("pending"):
        target = revision["target"]
        route = target
        await say(f"Revizyon: {AGENT_BY_ID[target]['role']} yeniden çalışacak")
        await bus.log(f"Kullanıcı revizyon istedi → {AGENT_BY_ID[target]['role']}: “{revision.get('note') or '-'}”",
                      agent="director", data=revision, job_id=job_id)
        out["revision"] = {**revision, "pending": False}
        out["fix_request"] = {"target": target, "reasons": [revision.get("note") or "Kullanıcı revizyonu"],
                              "source": "user"}
        out["qa_rounds"] = 0
        out["retries"] = {}
        step_status = _reset_downstream(step_status, target)
    elif not state.get("started"):
        topic = (state.get("topic") or "").strip() or daily_topic()
        await say(f"Günün konusu: “{topic}”")
        await bus.log(
            f"Yeni üretim başlatıldı. Konu: “{topic}”" + ("" if state.get("topic") else " (günlük konu listesinden)"),
            agent="director",
            data={"job_id": job_id, "topic": topic, "mock_mode": settings.mock_mode, "options": state.get("options")},
            job_id=job_id,
        )
        out.update(topic=topic, started=True)
        route = "storyteller"
    else:
        route = "storyteller"

    if settings.mock_mode:
        import asyncio

        await asyncio.sleep(0.8 * settings.mock_step_delay)

    history.append({"route": route, "reason": "failed" if failed else "qa" if qa_fb else
                    "revision" if revision.get("pending") else "start"})
    out.update(route=route, history=history, step_status=step_status, last_agent="director")
    db.finish_step(step_id, route != "fail")
    if route != "fail":
        await say(f"Akış → {AGENT_BY_ID[route]['role']}")
    await persist_state(job_id, {**state, **out}, status="running")
    return out


def route_from_director(state: dict) -> str:
    return state.get("route") or "storyteller"
