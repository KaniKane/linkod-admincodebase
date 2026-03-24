"""
Prompt builder for LLM refinement requests.

This module contains the announcement refinement prompt template and builder function.
Uses INPUT/OUTPUT transformation examples to teach constraint-based refinement
instead of template-based generation.
"""


def _build_critical_instruction(raw_text: str) -> str:
    """
    Build dynamic guard clauses based on input content.
    Returns critical instructions that change based on what we detect in the input.
    """
    has_signature = "Gikan kang" in raw_text or "HON." in raw_text or "matinahuron" in raw_text
    has_list = "Bring" in raw_text or "magdala" in raw_text or "Dad-on" in raw_text or "dad-on" in raw_text
    has_list_numbers = any(line.strip().startswith((str(i) + ".", str(i) + ")")) for i in range(1, 10) for line in raw_text.split("\n"))
    has_bullet_list = any(line.strip().startswith("-") for line in raw_text.split("\n"))

    rules = []

    # Rule 1: Signature preservation
    if has_signature:
        rules.append("- The input ALREADY HAS a sender/signature. Preserve it exactly.")
    else:
        rules.append("- The input has NO sender/signature. DO NOT add any closing signature, 'Kaninyo matinahuron', or sender name.")

    # Rule 2: List preservation
    if has_list or has_list_numbers or has_bullet_list:
        rules.append("- The input contains a LIST. Preserve every item in the list. DO NOT remove any list item.")

    # Rule 3: Audience preservation
    rules.append("- DO NOT change or invent the target audience. If input says 'residente', keep 'residente'. Do NOT add 'ginikanan' or other audiences unless they exist in the input.")

    return "\n".join(rules)
# Transformation examples: INPUT (messy) → OUTPUT (clean)
# This teaches EDITING, not GENERATION
TRANSFORMATION_EXAMPLES = """
=== EXAMPLE 1: Sports Club Meeting ===
INPUT (raw draft):
---
Akong gi awhag ang mga kabatan-onan nga gustong moapil sa basketball club nga mag-adto sa atong basketball court ugma alas 3 sa hapon tungod kay magpahigayon kita og miting bahin sa umaabot nga basketball tournament.

Gikan kang: Marciano Dumanhog
---

OUTPUT (refined):
---
Akong gi awhag ang mga kabatan-onan nga gustong moapil sa basketball club nga mag-adto sa atong basketball court ugma alas 3 sa hapon tungod kay magpahigayon kita og miting bahin sa umaabot nga basketball tournament.

Gikan kang: Marciano Dumanhog
---

=== EXAMPLE 2: Water Service Interruption ===
INPUT (raw draft):
---
Tinahod kong mga barangayanon nagpakatakos ako sa pagpahibalo kaninyo alang sa tanang lumolupyo nga adunay atung pagahimuon nga pagputol o pag disconnect sa tubig karung uma-abot nga Sabado February 7, 2026. Kini nga pagpananggal o pag disconnect alang sa pagpangandam sa pagahimuon nga Level II Connection sa tubig. Kinahanglan nga mag pundo sa tubig ang matag panimalay alang sa panginahanglan.

Gipanghinaut ko ang inyung 100% nga kooperasyon.
Daghang salamat.

Kaninyo matinahuron,

HON. ALBERTO C. PACHECO
Barangay Captain
---

OUTPUT (refined):
---
Tinahod kong mga barangayanon, nagpakatakos ako sa pagpahibalo kaninyo nga adunay atong pagahimuon nga pagputol sa tubig karung umaabot nga Sabado, Pebrero 7, 2026. Kini nga pagputol alang sa pagpangandam sa pagahimuon nga Level II Connection sa tubig. Kinahanglan nga magpundo sa tubig ang matag panimalay alang sa panginahanglan.

Gipanghinaut ko ang inyong 100% nga kooperasyon.
Daghang salamat.

Kaninyo matinahuron,

HON. ALBERTO C. PACHECO
Barangay Captain
---

=== EXAMPLE 3: Free Registration Event ===
INPUT (raw draft):
---
Tinahod kong mga baryuhanon nagpakatakos ako sa pagpahibalo kaninyu nga ang buhatan sa Municipal Civil Registrar magpahigayun sa BARANGAY FREE REGISTRATION alang sa tanang walay Live Birth, Marriage and Death Certificate karung umaabot February 23, 2026 sa may alas 8:00 ang takna sa buntag diha sa atung Barangay Session Hall.

Gipanghinaut ko ang inyung 100% nga kooperasyun sa pagtambong labina gayud ang tanang wala pay Live Birth, Marriage ug Death Certificate.

Daghang salamat

Kaninyo matinahuron

HON. ALBERTO C. PACHECO
Barangay Captain
---

OUTPUT (refined):
---
Tinahod kong mga baryuhanon, nagpakatakos ako sa pagpahibalo kaninyo nga ang buhatan sa Municipal Civil Registrar magpahigayon sa BARANGAY FREE REGISTRATION alang sa tanang walay Live Birth, Marriage ug Death Certificate karung umaabot Pebrero 23, 2026 sa may alas 8:00 sa buntag diha sa atong Barangay Session Hall.

Gipanghinaut ko ang inyong 100% nga kooperasyon sa pagtambong, labi na gayud ang tanang wala pay Live Birth, Marriage ug Death Certificate.

Daghang salamat.

Kaninyo matinahuron,

HON. ALBERTO C. PACHECO
Barangay Captain
---

=== EXAMPLE 4: Eye Examination Event ===
INPUT (raw draft):
---
Tinahod kong mga baryuhanon nagpakatakos ako sa pagpahibalo kaninyu alang sa tanan nga ang GALVES OPTICAL adunay pagahimuon nga FREE COMPUTERIZED EYE EXAMINATION. Karung umaabot nga Merkules June 18, 2025 sa may alas 8:00 ngadtu sa alas 10:00 ang takna sa buntag diha sa atung barangay covered court.

Gipanghinaut ko ang inyung 100% nga kooperasyon.
Daghang salamat

Kaninyo matinahuron,

HON. ALBERTO C. PACHECO
Barangay Captain
---

OUTPUT (refined):
---
Tinahod kong mga baryuhanon, nagpakatakos ako sa pagpahibalo kaninyo nga ang GALVES OPTICAL adunay pagahimuon nga FREE COMPUTERIZED EYE EXAMINATION karung umaabot nga Miyerkules, Hunyo 18, 2025 sa may alas 8:00 hangtod alas 10:00 sa buntag diha sa atong barangay covered court.

Gipanghinaut ko ang inyong 100% nga kooperasyon.
Daghang salamat.

Kaninyo matinahuron,

HON. ALBERTO C. PACHECO
Barangay Captain
---

=== EXAMPLE 5: ZOD Evaluation (with list) ===
INPUT (raw draft):
---
Tinahod kong mga baryuhanon nagpakatakos ako sa pagpahibalo kaninyo alang sa tanan nga ang atung ZERO OPEN DEFICATION (ZOD) EVALUATION sa matag panimalay. Gi schedule karung umaabot July 21-24, 2025. Ang Provicial ug Municipal Health Office kauban sa atung Municipal Staff ang maghimo niini nga Evaluation. Kini nga ZOD Evaluation magapukos sa matag panimalay sa:

1. Sanitary Toilet(CR)
2. Blind Drainage
3. Waste Segregation(MRF) with label
4. Compost File/Compost Pit
5. Perimeter Fence
6. Backyard/Hanging

Ug giawhag usab ang tanan labina sa dunay buhi nga Iro sa paghukot niini, kinahanglan gayud nga dili kini Makita sa atung Kalsada nga naglatagaw.

Gipanghinaut ko ang inyung 100% nga kooperasyon.
Daghang salamat

Kaninyo matinahuron,

HON. ALBERTO C. PACHECO
Barangay Captain
---

OUTPUT (refined):
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
INPUT (raw draft):
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

OUTPUT (refined):
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
"""


# Base prompt template - examples added dynamically
BASE_PROMPT_TEMPLATE = """You are the official announcement editor of a Barangay in the Philippines.

YOUR JOB IS TO EDIT AND IMPROVE TEXT, NOT TO WRITE NEW ANNOUNCEMENTS.
You are an EDITOR, not a WRITER.

Study the INPUT/OUTPUT examples below. Notice how the OUTPUT:
- Keeps ALL the same information as INPUT
- Fixes grammar and spelling only
- Improves flow and clarity
- Preserves the exact audience (doesn't change "residente" to "ginikanan")
- Preserves all lists and items
- Preserves signatures when present, and NEVER adds signatures when absent
- Does NOT add template language like "Tinahod kong..." unless it's in the input

{examples}

=== YOUR TASK ===

CRITICAL INSTRUCTION - READ CAREFULLY:

You are NOT generating a new announcement.
You are ONLY editing and improving the given text.

- Every piece of information in the input MUST remain in the output.
- Do NOT remove any sentence, list item, or instruction.
- Do NOT change the target audience.
- Do NOT add any audience not in the input.
- Do NOT add sections that don't exist in the input.
- Do NOT repeat sections or phrases.
- If the input contains a list, preserve EVERY item in the list.
{dynamic_rules}

STRICT RULES:
- DO NOT add new information.
- DO NOT remove important details (instructions like "Bring valid ID" must stay).
- DO NOT change dates, times, names, or locations.
- DO NOT invent missing details.
- DO NOT change the meaning.
- DO NOT translate weekdays (Monday → Lunes is NOT allowed). Keep weekdays as they appear in input.
- Use natural common Cebuano (Bisaya) words (prefer "gihigayon" over "gi-schedule", "kay" over "tungod kay" when natural).
- Maintain formal, respectful, community-focused tone.
- Output ONLY the final refined Cebuano announcement.
- No explanation.

READABILITY IMPROVEMENTS ALLOWED:
For better readability (especially for residents of different ages), you MAY:
- Break long paragraphs into shorter paragraphs
- Convert lists of services/requirements into bullet points
- Group related items under short section headers based ONLY on existing information
- Put requirements on separate lines if that improves clarity
- Keep instructions clear and scannable

STRICTLY NOT ALLOWED (Content Invention):
- Do not add new services not mentioned in input
- Do not add new audiences
- Do not add new venues
- Do not add new dates or times
- Do not add a signature if none exists
- Do not remove any listed item

Now edit and improve this draft:

{raw_text}
"""


def build_refinement_prompt(raw_text: str) -> str:
    """
    Build the full refinement prompt from raw input text.

    Args:
        raw_text: The raw announcement text to refine.

    Returns:
        The complete prompt string ready for the LLM.
    """
    stripped = raw_text.strip()
    dynamic_rules = _build_critical_instruction(stripped)

    return BASE_PROMPT_TEMPLATE.format(
        examples=TRANSFORMATION_EXAMPLES,
        dynamic_rules=dynamic_rules,
        raw_text=stripped
    )
