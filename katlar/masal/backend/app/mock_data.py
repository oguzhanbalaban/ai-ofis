"""Mock mod için hazır, özgün çocuk hikayeleri (3-8 yaş, pozitif mesajlı)."""
from __future__ import annotations

import datetime as _dt
import hashlib

DAILY_TOPICS = [
    "paylaşmak",
    "sabırlı olmak",
    "cesaret",
    "yardımlaşma",
    "dürüstlük",
    "doğayı korumak",
    "farklılıklara saygı",
    "teşekkür etmek",
]

STORIES = [
    {
        "key": "paylasmak",
        "keywords": ["paylaş", "paylas", "cömert", "comert", "elma"],
        "title": "Pıtpıt ve Kocaman Kırmızı Elma",
        "moral": "Paylaşınca mutluluk büyür.",
        "hero": {"name": "Pıtpıt", "species": "bunny", "color": "#f4efe6", "accent": "#f7a8b8"},
        "scenes": [
            {"text": "Bir sabah Pıtpıt, ormandaki en kocaman kırmızı elmayı buldu! Ama küçük bir sorun vardı.",
             "setting": "orman", "time": "sabah", "prop": "apple"},
            {"text": "Elma o kadar büyüktü ki, minik tavşan onu tek başına bir adım bile taşıyamadı.",
             "setting": "orman", "time": "sabah", "prop": "apple"},
            {"text": "Tam o sırada Sincap Fındık daldan atladı. Yardım edeyim mi, diye sordu gülümseyerek.",
             "setting": "orman", "time": "gun", "prop": "friend"},
            {"text": "Kirpi Diken de koşarak geldi. Üç arkadaş elmayı tepeden yavaşça birlikte yuvarladılar.",
             "setting": "tepe", "time": "gun", "prop": "apple"},
            {"text": "Yuvaya varınca Pıtpıt bir an düşündü: Bu elmayı tek başıma yiyebilirim.",
             "setting": "yuva", "time": "aksam", "prop": "apple"},
            {"text": "Sonra yorgun ama mutlu arkadaşlarına baktı. Elmayı üç eşit parçaya böldü.",
             "setting": "yuva", "time": "aksam", "prop": "heart"},
            {"text": "Birlikte yediler, birlikte güldüler. Elma hiç bu kadar tatlı olmamıştı!",
             "setting": "yuva", "time": "aksam", "prop": "friend"},
            {"text": "Çünkü paylaşınca mutluluk büyür. Peki sen bugün neyini paylaşacaksın?",
             "setting": "orman", "time": "gece", "prop": "star"},
        ],
    },
    {
        "key": "sabir",
        "keywords": ["sabır", "sabir", "bekle", "tohum", "çiçek", "cicek"],
        "title": "Tosba'nın Sihirli Tohumu",
        "moral": "Güzel şeyler sabırla büyür.",
        "hero": {"name": "Tosba", "species": "turtle", "color": "#8fd19e", "accent": "#5b9e6b"},
        "scenes": [
            {"text": "Kaplumbağa Tosba'nın elinde sihirli bir tohum vardı! Ama bu tohum ne zaman büyüyecekti?",
             "setting": "bahce", "time": "sabah", "prop": "seed"},
            {"text": "Tosba tohumu bahçenin ortasına ekti ve her sabah onu sevgiyle suladı.",
             "setting": "bahce", "time": "sabah", "prop": "water"},
            {"text": "Bir gün geçti, iki gün geçti. Toprakta hâlâ hiçbir şey görünmüyordu.",
             "setting": "bahce", "time": "gun", "prop": "seed"},
            {"text": "Tavşan Zıpzıp kıkırdadı: Boşuna bekliyorsun Tosba, artık vazgeç!",
             "setting": "bahce", "time": "gun", "prop": "friend"},
            {"text": "Ama Tosba vazgeçmedi. Güneşi, yağmuru ve rüzgârı sabırla bekledi.",
             "setting": "bahce", "time": "aksam", "prop": "rain"},
            {"text": "Bir sabah topraktan minicik, yemyeşil bir filiz başını uzattı!",
             "setting": "bahce", "time": "sabah", "prop": "sprout"},
            {"text": "Filiz her gün biraz daha uzadı ve sonunda kocaman, rengârenk bir çiçek açtı.",
             "setting": "bahce", "time": "gun", "prop": "flower"},
            {"text": "Zıpzıp şaşkınlıkla baktı. Tosba gülümsedi: Güzel şeyler sabırla büyür. Sen neyi bekliyorsun?",
             "setting": "bahce", "time": "aksam", "prop": "flower"},
        ],
    },
    {
        "key": "cesaret",
        "keywords": ["cesaret", "korku", "karanlık", "karanlik", "gece", "yıldız", "yildiz"],
        "title": "Ayıcık Bal ve Gece Işıkları",
        "moral": "Cesaret, korkuya rağmen bir adım atmaktır.",
        "hero": {"name": "Bal", "species": "bear", "color": "#c98b55", "accent": "#f1c27d"},
        "scenes": [
            {"text": "Ayıcık Bal karanlıktan çok korkardı. Ama bu gece her şey değişecekti!",
             "setting": "oda", "time": "gece", "prop": "moon"},
            {"text": "Yatağına uzandı ve pencereden süzülen gölgelere baktı. Kalbi pıt pıt atıyordu.",
             "setting": "oda", "time": "gece", "prop": "moon"},
            {"text": "Birden pencerede minicik bir ışık belirdi. Bu, Ateşböceği Işıl'dı!",
             "setting": "oda", "time": "gece", "prop": "firefly"},
            {"text": "Korkma Bal, dedi Işıl. Gel, karanlığın güzelliklerini birlikte keşfedelim.",
             "setting": "oda", "time": "gece", "prop": "firefly"},
            {"text": "Bal derin bir nefes aldı ve cesaretini toplayıp bahçeye çıktı.",
             "setting": "orman", "time": "gece", "prop": "firefly"},
            {"text": "Gökyüzünde binlerce yıldız parlıyordu. Ay, gülümseyen bir yüz gibiydi.",
             "setting": "tepe", "time": "gece", "prop": "star"},
            {"text": "Baykuş Bilge selam verdi, cırcır böcekleri yumuşacık bir ninni söylüyordu.",
             "setting": "orman", "time": "gece", "prop": "friend"},
            {"text": "Bal o gece öğrendi: Cesaret, korkuya rağmen bir adım atmaktır. Sen de dener misin?",
             "setting": "tepe", "time": "gece", "prop": "star"},
        ],
    },
    {
        "key": "yardim",
        "keywords": ["yardım", "yardim", "iyilik", "dost", "arkadaş", "arkadas", "bulut", "yağmur"],
        "title": "Küçük Bulut Pofuduk",
        "moral": "İyilik yapan herkes büyüktür.",
        "hero": {"name": "Pofuduk", "species": "cloud", "color": "#ffffff", "accent": "#a9d6ff"},
        "scenes": [
            {"text": "Küçük bulut Pofuduk ağlamaya başladı ve bütün kasabayı ıslattı! Ama neden?",
             "setting": "kasaba", "time": "gun", "prop": "rain"},
            {"text": "Çünkü büyük bulutlar onu çok küçük bulmuş ve oyunlarına almamıştı.",
             "setting": "gokyuzu", "time": "gun", "prop": "friend"},
            {"text": "Aşağıda, kurumuş bir tarlada Çiftçi Nine üzgün üzgün gökyüzüne bakıyordu.",
             "setting": "tarla", "time": "gun", "prop": "seed"},
            {"text": "Pofuduk'un damlaları tarlaya düşünce buğdaylar başlarını kaldırdı.",
             "setting": "tarla", "time": "gun", "prop": "rain"},
            {"text": "Çiçekler açtı, kuşlar şarkı söyledi, çocuklar su birikintilerinde zıpladı.",
             "setting": "kasaba", "time": "gun", "prop": "flower"},
            {"text": "Çiftçi Nine el salladı: Teşekkürler küçük bulut, sen bir kahramansın!",
             "setting": "tarla", "time": "aksam", "prop": "heart"},
            {"text": "Büyük bulutlar bunu görünce utandılar ve Pofuduk'tan özür dilediler.",
             "setting": "gokyuzu", "time": "aksam", "prop": "friend"},
            {"text": "Küçük olmak önemli değil; iyilik yapan herkes büyüktür. Sen bugün kime yardım edeceksin?",
             "setting": "gokyuzu", "time": "aksam", "prop": "heart"},
        ],
    },
]


# Görsel motorları (FLUX / fal / OpenAI) için İngilizce sahne betimlemeleri. Gerçek modda bunları
# Senarist LLM'i yazar; mock hikayelerde elle yazılmış hâlleri kullanılır. Karakter tarifleri her
# sahnede aynı kalır ki kahraman videonun başından sonuna aynı görünsün.
VISUALS = {
    "paylasmak": {
        "hero_en": "a small fluffy white bunny with long pink-lined ears, big sparkly brown eyes, rosy cheeks "
                   "and a tiny pink nose",
        "scenes": [
            "Pıtpıt the bunny discovers an enormous shiny red apple, bigger than the bunny itself, lying on the "
            "mossy forest floor, eyes wide with surprise",
            "Pıtpıt pushes the giant red apple with both paws, straining with a funny determined face, but the "
            "apple does not move at all",
            "a red squirrel with a big bushy tail leaps down from a tree branch toward Pıtpıt and the giant red "
            "apple, smiling and offering to help",
            "Pıtpıt, the red squirrel and a small hedgehog with soft brown spines roll the giant red apple "
            "together down a grassy hill, laughing",
            "inside a cozy burrow home with round wooden furniture, Pıtpıt sits next to the giant red apple with "
            "a paw on the chin, thinking",
            "Pıtpıt cuts the red apple into three equal pieces on a little wooden table while the red squirrel "
            "and the small hedgehog watch happily",
            "Pıtpıt, the red squirrel and the small hedgehog eat apple slices together around a little table, "
            "laughing, warm lamp light",
            "Pıtpıt waves at the viewer with a warm smile in the forest under a starry night sky, fireflies "
            "twinkling",
        ],
    },
    "sabir": {
        "hero_en": "a small friendly green turtle with a glossy emerald-green shell with lighter hexagon patterns, "
                   "big kind dark eyes and a gentle smile",
        "scenes": [
            "Tosba the little turtle carefully holds a tiny glowing magic seed, looking at it with curiosity in a "
            "sunny garden",
            "Tosba plants the seed in the middle of the garden and waters it with a small blue watering can",
            "Tosba sits patiently beside a small patch of bare brown soil where nothing has sprouted yet",
            "a playful grey bunny giggles and points at the empty patch of soil while Tosba stays calm",
            "Tosba waits patiently in the garden under gentle rain, holding a big green leaf as an umbrella",
            "a tiny bright green sprout pokes out of the soil and Tosba leans in with a delighted, surprised smile",
            "a big colorful flower in full bloom towers over Tosba, who looks up at it happily",
            "the grey bunny stares amazed at the big colorful flower while Tosba smiles warmly at the viewer",
        ],
    },
    "cesaret": {
        "hero_en": "a chubby honey-brown bear cub with round ears, a cream-colored muzzle, big dark eyes and a tiny "
                   "red knitted scarf",
        "scenes": [
            "Bal the bear cub peeks out nervously from under a blanket in a bedroom at night, moonlight coming "
            "through the window",
            "Bal lies in bed holding the blanket tight, looking at soft shadows on the wall from the moonlit window",
            "a tiny glowing firefly with a warm golden light appears at the window and Bal looks up in surprise",
            "the friendly glowing firefly hovers near Bal's face, smiling, its warm light filling the cozy room",
            "Bal takes a brave first step out into the night garden, following the glowing firefly",
            "Bal stands on a hilltop looking up at thousands of twinkling stars and a big gentle smiling moon",
            "a wise brown owl with big round eyes greets Bal from a tree branch in the softly lit night forest",
            "Bal stands proudly on the hilltop under the starry sky, smiling confidently at the viewer, the glowing "
            "firefly beside",
        ],
    },
    "yardim": {
        "hero_en": "a tiny puffy white cloud with a cute face, big shiny eyes, rosy cheeks and soft light-blue edges",
        "scenes": [
            "Pofuduk the tiny cloud cries gentle raindrops over a small pastel village where umbrellas pop open",
            "big fluffy clouds play together in the sky and turn away from tiny Pofuduk, who looks lonely",
            "a kind elderly farmer grandmother in a straw hat looks up hopefully at the sky from a dry field",
            "Pofuduk's raindrops fall on the dry field and the golden wheat stalks lift their heads, refreshed",
            "flowers bloom, birds sing and children in colorful raincoats jump in puddles in the pastel village "
            "while Pofuduk smiles above",
            "the farmer grandmother in the straw hat waves happily up at Pofuduk, a rainbow over the green field",
            "the big clouds gather around Pofuduk and gently hug the tiny cloud in a pink sunset sky",
            "Pofuduk glows happily among the other clouds in the sunset sky, smiling at the viewer, a rainbow behind",
        ],
    },
}


def _with_visuals(story: dict) -> dict:
    vis = VISUALS.get(story["key"], {})
    out = {**story, "hero": {**story["hero"]}, "scenes": [dict(s) for s in story["scenes"]]}
    if vis.get("hero_en"):
        out["hero"]["description_en"] = vis["hero_en"]
    for sc, line in zip(out["scenes"], vis.get("scenes", [])):
        sc["visual_en"] = line
    return out


def daily_topic(today: _dt.date | None = None) -> str:
    today = today or _dt.date.today()
    return DAILY_TOPICS[today.toordinal() % len(DAILY_TOPICS)]


def pick_story(topic: str, variant: int = 0) -> dict:
    """Konuya en uygun hazır hikayeyi seç; revizyonlarda bir sonrakine geç."""
    low = (topic or "").lower()
    idx = None
    for i, s in enumerate(STORIES):
        if any(k in low for k in s["keywords"]):
            idx = i
            break
    if idx is None:
        idx = int(hashlib.sha1(low.encode("utf-8")).hexdigest(), 16) % len(STORIES)
    return _with_visuals(STORIES[(idx + variant) % len(STORIES)])
