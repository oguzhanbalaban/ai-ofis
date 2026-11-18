"""3. Art Director Agent (Görsel Yönetmen): sabit stil/karakter çapası ile 9:16 sahne promptları."""
from __future__ import annotations

import hashlib

from .. import pricing
from ..services import llm
from .base import AgentContext, agent_node

# Belirli bir stüdyo/marka adı kullanılmaz; stil tarif edilir.
STYLE_ANCHOR = (
    "charming 3D animated children's movie still, soft rounded shapes, gentle pastel color palette, "
    "warm soft lighting with subtle rim light, big expressive eyes, cozy and safe atmosphere, "
    "rich detailed textures, shallow depth of field, vertical portrait composition with the characters "
    "in the upper half and calm uncluttered ground in the lower third, no text, no letters"
)
NEGATIVE = "text, letters, watermark, logo, scary, dark horror, violence, weapons, realistic photo, deformed, extra limbs"

SPECIES_EN = {
    "bunny": "a small fluffy white bunny with long pink-lined ears, big sparkly brown eyes and rosy cheeks",
    "bear": "a chubby honey-brown bear cub with round ears, a light muzzle and a tiny red scarf",
    "turtle": "a friendly little green turtle with a glossy emerald shell and a gentle smile",
    "cloud": "a tiny puffy white cloud with a sweet face, blue-tinted edges and rosy cheeks",
}
SETTING_EN = {
    "orman": "a sunny enchanted forest with soft mossy ground and round trees",
    "tepe": "a gentle grassy hilltop with wildflowers",
    "yuva": "a cozy rabbit burrow home with warm wooden furniture",
    "bahce": "a colorful vegetable garden with a little wooden fence",
    "oda": "a cozy child bedroom with a big window and a soft bed",
    "kasaba": "a cheerful tiny village with pastel houses",
    "tarla": "a golden wheat field under a wide sky",
    "gokyuzu": "a dreamy sky full of fluffy clouds",
}
TIME_EN = {"sabah": "early morning light", "gun": "bright daylight", "aksam": "warm sunset glow", "gece": "magical starry night"}
PROP_EN = {
    "apple": "a giant shiny red apple", "friend": "a cute woodland friend nearby", "heart": "a warm feeling of love",
    "star": "twinkling stars", "seed": "a tiny magic seed", "water": "a small watering can", "rain": "gentle rain drops",
    "sprout": "a tiny green sprout", "flower": "a big colorful flower", "moon": "a smiling moon",
    "firefly": "glowing fireflies",
}


def hero_description(hero: dict) -> str:
    return hero.get("description_en") or SPECIES_EN.get(hero.get("species", ""), "a cute small animal character")


def character_anchor(hero: dict) -> str:
    return f"{hero.get('name', 'Hero')} is {hero_description(hero)}. Same character design and colors in every scene."


def reference_prompt(hero: dict) -> str:
    """Yerel FLUX'un karakter tutarlılığı için ilk çizdiği referans görselin istemi."""
    return (f"Character design reference of {hero.get('name', 'the hero')}, {hero_description(hero)}, "
            f"full body, front view, standing, friendly smile, centered on a plain soft pastel background. "
            f"Style: {STYLE_ANCHOR}.")


def seed_for(hero: dict, topic: str) -> int:
    return int(hashlib.sha1(f"{hero.get('name')}-{topic}".encode()).hexdigest(), 16) % 2_147_483_647


@agent_node("art_director", "Stil çapası hazırlanıyor…")
async def art_director_node(state: dict, ctx: AgentContext) -> dict:
    story = state["story"]
    hero = story.get("hero", {})
    anchor = character_anchor(hero)
    seed = seed_for(hero, story.get("topic", ""))
    fix = state.get("fix_request") or {}
    await ctx.say("Stil & karakter çapası sabitleniyor…")
    await ctx.pace(0.8)

    visual_lines = {}
    if not ctx.mock and not all(s.get("visual_en") for s in story["scenes"]):
        await ctx.say("LLM ile sahne betimlemeleri…")
        data, pc, oc = await llm.complete_json(
            "You convert Turkish children's story scenes into short English visual descriptions. Return JSON only.",
            "Return {\"scenes\": [{\"index\": int, \"visual_en\": str}]} for:\n"
            + "\n".join(f"{s['index']}. {s['text']}" for s in story["scenes"]),
        )
        visual_lines = {int(x["index"]): x["visual_en"] for x in data.get("scenes", [])}
        ctx.add_cost(pricing.llm_cost(pc, oc))
    else:
        ctx.add_cost(pricing.llm_cost(1200, 900))  # gerçek modda tahmini

    scenes = []
    for sc in story["scenes"]:
        await ctx.say(f"Sahne {sc['index']} promptu yazılıyor…")
        await ctx.pace(0.25)
        action = sc.get("visual_en") or visual_lines.get(sc["index"]) or (
            f"{hero.get('name', 'the hero')} with {PROP_EN.get(sc.get('prop', ''), 'a happy expression')}"
        )
        # Görsel modelleri istemin başına daha çok ağırlık verir: önce eylem, sonra karakter, mekân, stil.
        prompt = (
            f"{action[:1].upper() + action[1:]}. {anchor} "
            f"Setting: {SETTING_EN.get(sc.get('setting', ''), sc.get('setting', 'storybook world'))}, "
            f"{TIME_EN.get(sc.get('time', ''), 'soft light')}. Style: {STYLE_ANCHOR}."
        )
        if fix.get("target") == "art_director" and fix.get("reasons"):
            prompt += " Extra direction: gentle, friendly, safe for kids."
        scenes.append({"index": sc["index"], "prompt": prompt, "action": action, "negative": NEGATIVE, "seed": seed,
                       "aspect_ratio": "9:16", "setting": sc.get("setting"), "time": sc.get("time"),
                       "prop": sc.get("prop")})
    art = {"style_anchor": STYLE_ANCHOR, "character_anchor": anchor, "seed": seed, "negative": NEGATIVE,
           "reference_prompt": reference_prompt(hero), "scenes": scenes}
    await ctx.say(f"{len(scenes)} prompt hazır ✓")
    await ctx.pace(0.4)
    out = {"art": art}
    if fix.get("target") == "art_director":
        out["fix_request"] = None
    return out
