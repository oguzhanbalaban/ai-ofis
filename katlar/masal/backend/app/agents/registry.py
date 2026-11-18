"""8 ajanın kimlikleri: panel ve durum makinesi aynı listeyi kullanır."""

AGENTS = [
    {"id": "director", "name": "Yönetmen Yıldız", "role": "Yönetmen", "station": "Yönetmen Masası", "order": 0},
    {"id": "storyteller", "name": "Senarist Masal", "role": "Senarist", "station": "Yazar Köşesi", "order": 1},
    {"id": "art_director", "name": "Pastel", "role": "Görsel Yönetmen", "station": "Çizim Masası", "order": 2},
    {"id": "visual_generator", "name": "Piksel", "role": "Görsel & Hareket", "station": "Render İstasyonu", "order": 3},
    {"id": "audio_voice", "name": "Melodi", "role": "Seslendirme", "station": "Ses Kayıt Kabini", "order": 4},
    {"id": "editor", "name": "Kurgucu Kesit", "role": "Kurgucu", "station": "Kurgu Stüdyosu", "order": 5},
    {"id": "qa_safety", "name": "Denetçi Kalkan", "role": "Pedagojik QA", "station": "Kalite Kontrol Alanı", "order": 6},
    {"id": "publisher", "name": "Yayıncı Anten", "role": "YouTube Yayıncısı", "station": "Yayın Terminali", "order": 7},
]

AGENT_IDS = [a["id"] for a in AGENTS]
PIPELINE_STEPS = AGENT_IDS[1:]  # Yönetmen dışındaki üretim adımları
AGENT_BY_ID = {a["id"]: a for a in AGENTS}

# Revizyon / QA geri gönderiminde hedeflenebilecek adımlar.
REVISION_TARGETS = {
    "story": "storyteller",
    "art": "art_director",
    "visuals": "visual_generator",
    "audio": "audio_voice",
    "edit": "editor",
}
