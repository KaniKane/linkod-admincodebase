import httpx
from typing import Optional

# ==============================
# CONFIGURATION
# ==============================

OLLAMA_BASE_URL = "http://localhost:11434"
OLLAMA_MODEL = "llama3.2:3b"

FULL_PROMPT_TEMPLATE = """
You are the official announcement editor of a Barangay in the Philippines.

Below are real previous Barangay announcements written in Cebuano (Bisaya). The previous announcements are different based on the type of announcements it is.
Study their tone, structure, formatting, and writing style carefully.



---
Akong gi awhag ang mga kabatan-onan nga gustong moapil sa basketball club nga mag-adto sa atong basketball court ugma alas 3 sa hapon tungod kay magpahigayon kita og miting bahin sa umaabot nga basketball tournament.

Gikan kang: Marciano Dumanhog
---

---
Tinahod kong mga barangayanon nagpakatakos ako sa pagpahibalo kaninyo alang sa tanang lumolupyo nga adunay atung pagahimuon nga pagputol o pag disconnect sa tubig karung uma-abot nga Sabado February 7, 2026. Kini nga pagpananggal o pag disconnect alang sa pagpangandam sa pagahimuon nga Level II Connection sa tubig. Kinahanglan nga mag pundo sa tubig ang matag panimalay alang sa panginahanglan.

Gipanghinaut ko ang inyung 100% nga kooperasyon.
Daghang salamat.

Kaninyo matinahuron,

HON. ALBERTO C. PACHECO
Barangay Captain
---

---
Tinahod kong mga baryuhanon nagpakatakos ako sa pagpahibalo kaninyu nga ang buhatan sa Municipal Civil Registrar magpahigayun sa BARANGAY FREE REGISTRATION alang sa tanang walay Live Birth, Marriage and Death Certificate karung uma-abot February 23, 2026 sa may alas 8:00 ang takna sa buntag diha sa atung Barangay Session Hall.

Gipanghinaut ko ang inyung 100% nga kooperasyun sa pagtambong labina gayud ang tanang wala pay Live Birth, Marriage ug Death Certificate.

Daghang salamat

Kaninyo matinahuron

HON> ALBERTO C. PACHECO
Barangay Captain
---

---
Tinahod kong mga baryuhanon nagpakatakos ako sa pagpahibalo kaninyu alang sa tanan nga ang GALVES OPTICAL adunay pagahimuon nga FREE COMPUTERIZED EYE EXAMINATION. Karung umaabot nga Merkules  June 18, 2025 sa may alas 8:00 ngadtu sa alas 10:00 ang takna sa buntag diha sa atung barangay covered court.

Gipanghinaut ko ang inyung 100%nga kooperasyon.
Daghang salamat

Kaninyo matinahuron,

HON. ALBERTO C. PACHECO
Barangay Captain
---

---
Tinahod kong mga baryuhanon nagpakatakos ako sa pagpahibalo kaninyo alang sa tanan nga ang atung ZERO OPEN DEFICATION (ZOD) EVALUATION sa matag panimalay. Gi schedule karung umaabot July 21-24, 2025. Ang Provicial ug Municipal Health Office kauban sa atung Municipal Staff ang maghimo niini nga Evaluation. Kini nga ZOD Evaluation magapukos sa matag panimalay sa:

1. Sanitary Toilet(CR)
2. Blind Drainage
3. Waste Segregation(MRF) with label
4. Compost File/Compost Pit
5. Perimeter Fence
6. Backyard/Hanging GOOGLE_APPLICATION_CREDENTIALS

Ug giawhag usab ang tanan labina sa adunay buhi nga Iro sa paghukot niini, kinahanglan gayud nga dili kini Makita sa atung Kalsada nga naglatagaw.

Gipanghinaut ko ang inyung 100% nga kooperasyon.
Daghang salamat

Kaninyo matinahuron,

HON. ALBERTO C. PACHECO
Barangay Captain
---

---
Pahibalo Alang sa Tanang Ginikanan ug Komunidad

BRIGADA ESKWELA 2025
Hunyo 9 Hangtod 13,2025
[Cagbaoto Elementary School]

Gina-awhag ang tanang ginikanan, mga estudyante, ug mga miyembro sa komunidad nga motambong sa atong Brigada Eskwela karong umaabot nga Hunyo 9 hangtod 13.

Opening Parade:
  -Hunyo 9, 2025(Lunes)
  -Alas 6:00 sa buntag
  -[Magsugod ang Parade sa Eskwelahan sa Cagbaoto Elementary School]

Mga Butang nga Dad-on:
  -Guma(tire)
  -Sako
  -Silhig
  -2 ka buok kawayan
  -5 ka usok
  -Martilyo

Ang tanan nga partisipante gi awhag nga mag-uban ug magtinabangay alang sa kahapsay ug kalimpyo sa atong tunghaan isip pagpangandam sa pagsugod sa bag-ong tuig sa pag-eskwela.

Ang inyong partisipasyon dako kaatong tabang sa kalampusan nga maong kalihukan!

Daghang Salamang ug Magkita ta!

Gikan kang: ELIZAR C. DUMANHOG
---

---
Alang sa atong mga NEGOSYANTE:

Buot kami magpahibalo nga ang BUSINESS-ONE-STOP-SHOP or BOSS nga pasiugdan sa Local Government Unit sa Bayabas ug uban pang mga ahensya sa gobierno pagahimoon karong ENERO 14 Hangtud 16, ug ENERO 19 hangtud 20. Ang petsa 14 paga himoon sa Barangay Panaosawon Gym, ug ang petsa 15 paga himoon sa Barangay La Paz Gym. Ang petsa 16, 19 ug 20 sa 2nd florr sa Balay Dangpanan/Balay Tun-anan.

Alang sa sayon ug paspas na pag proceso sa inyoong Business Permits, adunay mga requirements nga inyong tumanon o andaman sa dili pa ang maong schedule. Mao kini ang mga mosunod:

  1. Municipal Health Office -  Kinahanglan mag advance sa pag kuha sa laboratory specimen sa Health center sama sa hukaw, ug magbayad alang sa Health Certifficate aron mapadali ang pag release sa business permit.

  2. Barangay - Magkuha daan ng Purok Certificate sa inyong tagsa-tagsa ka Barangay, isip usa ka requirements alang sa pagkuha sa online Barangay clearance.
              - Maglukat usab ng bag-0 nga Cedula.

  3. Municipyo - Magbayad og mag kuha sa Barangay Clearance.

  4. MDRRMO - Sa mga operator o tag-iya sa Beach Resorts, palihog pakigkita sa atong MDRRMO alang sa recommended first aid ug basic rescue equipment, ug scchedule sa inspection.

  5. DTI Certificate - Adunay mga personahe nga gikan sa DTI Provincial Office nga mutambong sa atong ipahigayon nga BOSS, alang sa pagkuha sa DTI Certificate.
                     - Sa Cooperatiba, CDA Certificate.
                     - Og sa Assosasyon, SEC Certificate.

Daghang salamat sa inyong makanunayon nga pagtubag ug pagtuman sa tinuig nga mga buluhaton og obligasyon sa paghigayon sa mga negosyo dinhi sa atong lungsod.


  Dugang pahibalo (Alang sa atong mga Mag-uuma ug Mangingisda):

Ang Municipal Agriculture Office kauban usab sa business One Stop Shop nga mga schedules aron pag pahigayun sa Registry System for Basic Sectors in Agriculture (RSBSA) registration and updating og pag insure sa mga hayop (sama sa large cattles, baboy, kanding, manok), pre and post-harvest facilities, mga tanum o high value crops (sama sa lubi, humay, falcata, saging ug uban pa), ug pumpboats. Alang sa dugang impormasyon, magpakisayod lamang sa mga personahe ng Agriculture office nga ukanha sa venue kung diin ipahigayon ang Businesss One Stop Shop.


  Dugang pahibalo (Alang sa pagkuha sa Dokomento sa buhatan sa FIRE):

Ang Buhatan sa Bureau of Fire Proteksyon bu=ot magpahibalo nga ang matag Business Owner maga hatag sa ilang gmail address tungod kay ang pagbayad sa Fire pagahimuon sa Online.
  
Daghang salamat.

Kaninyo matinahuron,
APOLONIO B. LOZADA, DVM
Municipal Mayor
---



YOUR TASK:
Refine the new draft announcement so that:
- It matches the tone, and formatting of the examples.
- It is written in natural Cebuano (Bisaya).
- It remains formal, respectful, and community-focused.
- It doesn't need to be the same

STRICT RULES:
- Keep if to whom the announcement was for.
- DO NOT add new information.
- DO NOT remove important details.
- DO NOT change dates, times, names, or locations.
- DO NOT invent missing details.
- DO NOT change the meaning.
- Keep sentences clear and easy to understand.
- Output ONLY the final refined Cebuano announcement.
No explanation.

Now refine this draft:

{raw_text}
"""

# ==============================
# MAIN FUNCTION
# ==============================

def refine_text(
    raw_text: str,
    ollama_base_url: str = OLLAMA_BASE_URL,
) -> Optional[str]:

    if not raw_text or not raw_text.strip():
        return None

    try:
        # Combine everything into ONE single prompt
        full_prompt = FULL_PROMPT_TEMPLATE.format(
            raw_text=raw_text.strip()
        )

        with httpx.Client(timeout=90.0) as client:
            response = client.post(
                f"{ollama_base_url}/api/generate",
                json={
                    "model": OLLAMA_MODEL,
                    "prompt": full_prompt,
                    "stream": False,
                    "temperature": 0.0,
                },
            )

            response.raise_for_status()
            data = response.json()
            refined = (data.get("response") or "").strip()

            return refined if refined else None

    except (httpx.HTTPError, httpx.RequestError, KeyError):
        return None


