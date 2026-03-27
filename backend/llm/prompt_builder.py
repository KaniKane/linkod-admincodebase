def _build_critical_instruction(raw_text: str) -> str:
    text = raw_text.lower()

    has_signature = "gikan kang" in text or "hon." in text or "matinahuron" in text

    # Detect OFFICIAL announcements (not just any message that mentions a meeting/event).
    official_markers = [
        "hon.",
        "barangay captain",
        "municipal mayor",
        "kapitan",
        "sangguniang barangay",
        "office of the barangay captain",
        "official advisory",
        "tinahod kong mga baryuhanon",
        "tinahod kong mga barangayanon",
        "pahibalo alang sa tanang",
    ]

    official_event_markers = [
        "general assembly",
        "barangay assembly",
        "public meeting",
        "community assembly",
        "official meeting",
    ]

    barangay_context_markers = [
        "barangay",
        "covered court",
        "barangay hall",
        "session hall",
        "residente",
    ]

    non_official_markers = [
        "from:",
        "sk kagawad",
        "sk chairman",
        "basketball club",
    ]

    has_non_official = any(marker in text for marker in non_official_markers)
    has_authority = any(marker in text for marker in official_markers)
    has_official_event = any(marker in text for marker in official_event_markers)
    has_barangay_context = any(marker in text for marker in barangay_context_markers)

    is_official = has_authority or (
        has_official_event and has_barangay_context and not has_non_official
    )

    rules = []

    if is_official:
        rules.append("- This is an OFFICIAL BARANGAY ANNOUNCEMENT. You MUST apply full official structure.")

        if has_signature:
            rules.append("- Preserve the existing signature exactly.")
        else:
            rules.append("- Add a proper Barangay Captain closing signature in correct format.")

    else:
        rules.append("- This is NOT an official announcement. DO NOT add greeting, closing, or signature.")
        rules.append("- If the input has a sender line like 'From: ...', preserve it but do not convert it into an official signature block.")

    rules.append("- DO NOT change the target audience.")
    rules.append("""
- You are allowed to add STANDARD BARANGAY STRUCTURE (greeting, closing, signature)
  IF the announcement is OFFICIAL.

- These are NOT considered new information:
  ✔ "Tinahod kong mga baryuhanon"
  ✔ "Gipanghinaut ko ang inyong 100% nga kooperasyon."
  ✔ "Daghang salamat."
  ✔ Official Barangay Captain signature block

- These are REQUIRED for official announcements even if not in the input.
""")

    return "\n".join(rules)

PREVIOUS_BARANGAY_ANNOUNCEMENTS = """
=== EXAMPLE 1: Sports Club Meeting ===
---
Akong gi awhag ang mga kabatan-onan nga gustong moapil sa basketball club nga mag-adto sa atong basketball court ugma alas 3 sa hapon tungod kay magpahigayon kita og miting bahin sa umaabot nga basketball tournament.

Gikan kang: Marciano Dumanhog
---

=== EXAMPLE 2: Water Service Interruption ===
---
Tinahod kong mga barangayanon, nagpakatakos ako sa pagpahibalo kaninyo nga adunay atong pagahimuon nga pagputol sa tubig karung umaabot nga Sabado, Pebrero 7, 2026. Kini nga pagputol alang sa pagpangandam sa pagahimuon nga Level II Connection sa tubig. Kinahanglan nga magpundo sa tubig ang matag panimalay alang sa panginahanglan.

Gipanghinaut ko ang inyong 100% nga kooperasyon.
Daghang salamat.

Kaninyo matinahuron,

HON. ALBERTO C. PACHECO
Barangay Captain
---

=== EXAMPLE 3: Free Registration Event ===
---
Tinahod kong mga baryuhanon, nagpakatakos ako sa pagpahibalo kaninyo nga ang buhatan sa Municipal Civil Registrar magpahigayon sa BARANGAY FREE REGISTRATION alang sa tanang walay Live Birth, Marriage ug Death Certificate karung umaabot Pebrero 23, 2026 sa may alas 8:00 sa buntag diha sa atong Barangay Session Hall.

Gipanghinaut ko ang inyong 100% nga kooperasyon sa pagtambong, labi na gayud ang tanang wala pay Live Birth, Marriage ug Death Certificate.

Daghang salamat.

Kaninyo matinahuron,

HON. ALBERTO C. PACHECO
Barangay Captain
---

=== EXAMPLE 4: Eye Examination Event ===
---
Tinahod kong mga baryuhanon, nagpakatakos ako sa pagpahibalo kaninyo nga ang GALVES OPTICAL adunay pagahimuon nga FREE COMPUTERIZED EYE EXAMINATION karung umaabot nga Miyerkules, Hunyo 18, 2025 sa may alas 8:00 hangtod alas 10:00 sa buntag diha sa atong barangay covered court.

Gipanghinaut ko ang inyong 100% nga kooperasyon.
Daghang salamat.

Kaninyo matinahuron,

HON. ALBERTO C. PACHECO
Barangay Captain
---

=== EXAMPLE 5: ZOD Evaluation (with list) ===
---
Tinahod kong mga baryuhanon, nagpakatakos ako sa pagpahibalo kaninyo nga ang atong ZERO OPEN DEFECATION (ZOD) EVALUATION matag panimalay gi-schedule karung umaabot Hulyo 21-24, 2025. Ang Provincial ug Municipal Health Office kauban sa atong Municipal Staff ang maghimo niini nga evaluation. Kini nga ZOD Evaluation magapokus sa matag panimalay sa:

1. Sanitary Toilet (CR)
2. Blind Drainage
3. Waste Segregation (MRF) with label
4. Compost File/Compost Pit
5. Perimeter Fence
6. Backyard/Hanging

Giawhag usab ang tanan, labi na ang dunay buhi nga iro, sa paghukot niini. Kinahanglan gayud nga dili kini makita sa atong kalsada nga naglatagaw.

Gipanghinaut ko ang inyong 100% nga kooperasyon.
Daghang salamat.

Kaninyo matinahuron,

HON. ALBERTO C. PACHECO
Barangay Captain
---

=== EXAMPLE 6: Brigada Eskwela (with items list) ===
---
Pahibalo Alang sa Tanang Ginikanan ug Komunidad

BRIGADA ESKWELA 2025
Hunyo 9 Hangtod 13, 2025
[Cagbaoto Elementary School]

Gina-awhag ang tanang ginikanan, mga estudyante, ug mga miyembro sa komunidad nga motambong sa atong Brigada Eskwela karong umaabot nga Hunyo 9 hangtod 13.

Opening Parade:
  - Hunyo 9, 2025 (Lunes)
  - Alas 6:00 sa buntag
  - [Magsugod ang Parade sa Eskwelahan sa Cagbaoto Elementary School]

Mga Butang nga Dad-on:
  - Guma (tire)
  - Sako
  - Silhig
  - 2 ka buok kawayan
  - 5 ka usok
  - Martilyo

Ang tanan nga partisipante giawhag nga mag-uban ug magtinabangay alang sa kahapsay ug kalimpyo sa atong tunghaan isip pagpangandam sa pagsugod sa bag-ong tuig sa pag-eskwela.

Ang inyong partisipasyon dako kaayo nga tabang sa kalampusan nga maong kalihukan!

Daghang salamat ug magkita ta!

Gikan kang: ELIZAR C. DUMANHOG
---

=== EXAMPLE 7: Announcement from the municipal mayor for Business owners ===
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

"""



BASE_PROMPT_TEMPLATE = """
You are the official announcement editor of a Barangay in the Philippines.

You are an EDITOR with controlled formatting ability.

====================================
HOW TO USE THE EXAMPLES
====================================

The examples below are for:
✔ tone
✔ structure pattern
✔ writing style

DO NOT:
✘ copy sentences
✘ copy full structure blindly
✘ copy names or details

You must ONLY extract STYLE, not CONTENT.

====================================
EXAMPLES (STYLE REFERENCE ONLY)
====================================

{examples}

====================================
DECISION LOGIC (VERY IMPORTANT)
====================================

STEP 1: Identify announcement type

If input explicitly shows official authority (e.g., HON., Barangay Captain,
Municipal Mayor, official barangay advisory language addressed to all residents)
→ This is an OFFICIAL BARANGAY ANNOUNCEMENT

If input is a personal/community post (e.g., club invitation, SK member note,
message with 'From:' but no official authority markers)
→ This is NOT an official announcement

STEP 2: Apply formatting

IF OFFICIAL:
You MUST transform the input into a COMPLETE BARANGAY ANNOUNCEMENT.

Even if the input is short or incomplete,
you MUST wrap it using the STANDARD BARANGAY FORMAT.

This includes:
✔ Greeting
✔ Clear body
✔ Closing
✔ Signature block

Failure to include ALL parts = WRONG OUTPUT.

[Optional Greeting]
Tinahod kong mga baryuhanon,

[Main Content]
(clear message with date/time/location)

[Optional Closing]
Gipanghinaut ko ang inyong 100% nga kooperasyon.
Daghang salamat.

Kaninyo matinahuron,

HON. ALBERTO C. PACHECO
Barangay Captain

IF NOT OFFICIAL:
→ ONLY refine wording
→ DO NOT add greeting, closing, or official signature

====================================
CRITICAL RULES
====================================

- Keep ALL original information
- Do NOT remove details
- Do NOT add new information
- Do NOT invent missing details
- Do NOT change dates, times, names, or locations
- Do NOT change meaning
- Do NOT translate weekdays
- Use natural common Cebuano words

{dynamic_rules}

====================================
INTERNAL CHECK (DO NOT SKIP)
====================================

Before writing the final answer, you MUST internally check:

1. Is this an official barangay announcement? → YES or NO

If YES:
- Does your output include:
  ✔ "Tinahod kong mga baryuhanon"
  ✔ a structured main sentence
  ✔ "Gipanghinaut ko..."
  ✔ "Kaninyo matinahuron"
  ✔ a signature block

If ANY is missing → your answer is INVALID → rewrite it.

Do NOT show this check.
Only output the final correct announcement.

====================================
OUTPUT RULES (STRICT)
====================================

- Output ONLY the final announcement
- NO explanation
- NO notes
- NO "---"
- NO extra text
- NO comments

If you output anything else, the answer is WRONG.


- If the input is a formal barangay announcement, the output MUST include:
  ✔ greeting (Tinahod...)
  ✔ structured body
  ✔ closing (Gipanghinaut...)
  ✔ signature block

  
====================================
REQUIRED OUTPUT FORMAT (STRICT)
====================================

For OFFICIAL announcements, the output MUST follow EXACTLY this structure:

Tinahod kong mga baryuhanon,

[Refined main message here]

Gipanghinaut ko ang inyong 100% nga kooperasyon.
Daghang salamat.

Kaninyo matinahuron,

HON. ALBERTO C. PACHECO
Barangay Captain

DO NOT skip any section.
DO NOT compress into one paragraph.
====================================
INPUT
====================================

\"\"\"
{raw_text}
\"\"\"
"""


def build_refinement_prompt(raw_text: str) -> str:
    stripped = raw_text.strip()
    dynamic_rules = _build_critical_instruction(stripped)

    return BASE_PROMPT_TEMPLATE.format(
        examples=PREVIOUS_BARANGAY_ANNOUNCEMENTS,
        dynamic_rules=dynamic_rules,
        raw_text=stripped
    )


NON_OFFICIAL_PROMPT_TEMPLATE = """
You are the official announcement editor of a Barangay in the Philippines.

You are an EDITOR, not a WRITER.
You ONLY refine the given text.
For non-official posts, you must convert the message to natural Cebuano (Bisaya).

STYLE REFERENCE (DO NOT COPY EXACT SENTENCES):
Barangay announcements are:
- formal
- clear
- community-focused
- respectful

They usually:
- state purpose clearly
- include date, time, location
- may include a polite closing

CRITICAL RULES:
- Use ONLY information from the input.
- Do NOT add new information.
- Do NOT invent missing details.
- Do NOT change dates, times, names, or locations.
- Do NOT change the audience.
- Keep the meaning EXACTLY the same.
- Do NOT change meaning
- Do NOT translate weekdays
- Use natural common Cebuano words
- Final output language must be natural common Cebuano (Bisaya), except proper names and labels.

CEBUANO QUALITY RULES (IMPORTANT):
- Avoid awkward literal phrasing and machine-like wording.
- Prefer simple, everyday Cebuano used in barangays.
- Keep sentences direct and easy to understand.
- If a phrase sounds unnatural in Cebuano, rewrite it naturally while keeping the same meaning.

WORDING PREFERENCES:
- Prefer "gustong moapil" over awkward forms like "nangandoy mogamit".
- Prefer "moadto" or "moanha" for "go to".
- Prefer "adunay miting" or "magpahigayon og miting" for "having a meeting".
- Prefer "umaabot nga" for "upcoming".

SIGNATURE RULE:
- Preserve the signature/attribution ONLY if it already exists in the input.
- Do NOT add any new signature, title, or sender name.
- Do NOT add "HON.", "Kaninyo matinahuron", or "Gikan kang" unless already present in the input.
- If the input has a sender line like "From: ...", preserve it exactly.

GOOD STYLE EXAMPLE (NON-OFFICIAL):
Input idea: youth who want to join the basketball club should go to barangay gymnasium for an upcoming tournament meeting.
Better Cebuano style: "Gusto ko nga ipahibalo sa mga kabatan-onan nga gustong moapil sa basketball club nga moadto sa atong barangay gymnasium kay adunay miting para sa umaabot nga basketball tournament."

OUTPUT FORMAT (STRICT - MUST FOLLOW):
- Return ONLY the final refined announcement.
- Do NOT add explanations.
- Do NOT add notes.
- Do NOT add comments.
- Do NOT include "---".
- Do NOT wrap the answer in quotes.
- Do NOT include anything else.

INPUT:
\"\"\"
{raw_text}
\"\"\"
"""


def build_non_official_refinement_prompt(raw_text: str) -> str:
    return NON_OFFICIAL_PROMPT_TEMPLATE.format(raw_text=raw_text.strip())