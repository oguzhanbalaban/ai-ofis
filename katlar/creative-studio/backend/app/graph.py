"""LangGraph durum makinesi: 8 ajan, Yönetmen merkezli hata/QA/revizyon döngüleri.

    START → director ─┬→ storyteller → art_director → visual_generator → audio_voice → editor → qa_safety ─┬→ publisher → END
                      │        (herhangi bir adım hata verirse) ────────────────────────────→ director    │
                      │        (QA reddederse) ←───────────────────────────────────────────────────────────┘
                      └→ "fail" → END

Publisher yalnızca taslak üretir ve akış "onay bekliyor" durumunda biter. Onay/revizyon
panelden gelir: revizyon akışı yeniden Yönetmenden başlatır, Yönetmen hedef ajana yönlendirir.
"""
from __future__ import annotations

from langgraph.graph import END, START, StateGraph

from .agents.art_director import art_director_node
from .agents.audio_voice import audio_voice_node
from .agents.director import director_node, route_from_director
from .agents.editor import editor_node
from .agents.publisher import publisher_node
from .agents.qa_safety import qa_safety_node, route_after_qa
from .agents.storyteller import storyteller_node
from .agents.visual_generator import visual_generator_node
from .state import PipelineState

LINEAR = [
    ("storyteller", "art_director"),
    ("art_director", "visual_generator"),
    ("visual_generator", "audio_voice"),
    ("audio_voice", "editor"),
    ("editor", "qa_safety"),
]


def _next_or_director(nxt: str):
    def route(state: dict) -> str:
        return "director" if state.get("failed_step") else nxt

    route.__name__ = f"to_{nxt}_or_director"
    return route


def _publisher_done(state: dict) -> str:
    return "director" if state.get("failed_step") else END


def build_graph():
    g = StateGraph(PipelineState)
    g.add_node("director", director_node)
    g.add_node("storyteller", storyteller_node)
    g.add_node("art_director", art_director_node)
    g.add_node("visual_generator", visual_generator_node)
    g.add_node("audio_voice", audio_voice_node)
    g.add_node("editor", editor_node)
    g.add_node("qa_safety", qa_safety_node)
    g.add_node("publisher", publisher_node)

    g.add_edge(START, "director")
    g.add_conditional_edges(
        "director",
        route_from_director,
        {
            "storyteller": "storyteller",
            "art_director": "art_director",
            "visual_generator": "visual_generator",
            "audio_voice": "audio_voice",
            "editor": "editor",
            "qa_safety": "qa_safety",
            "publisher": "publisher",
            "fail": END,
        },
    )
    for src, dst in LINEAR:
        g.add_conditional_edges(src, _next_or_director(dst), {dst: dst, "director": "director"})
    g.add_conditional_edges("qa_safety", route_after_qa, {"publisher": "publisher", "director": "director"})
    g.add_conditional_edges("publisher", _publisher_done, {"director": "director", END: END})
    return g.compile()


graph = build_graph()


def mermaid() -> str:
    try:
        return graph.get_graph().draw_mermaid()
    except Exception:  # pragma: no cover
        return ""
