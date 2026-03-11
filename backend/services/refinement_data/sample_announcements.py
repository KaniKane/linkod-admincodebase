"""
Sample announcement pairs for the simplified AI refinement system.

MINIMAL-EDIT EXAMPLES - These teach the AI to be a strict editor, not a template generator.

Rules for all examples:
- No signature blocks added
- No official names unless already in source
- No forced closing lines
- No "Daghang salamat" unless already in source
- Minimal grammar/spelling fixes only
- Preserve detail level exactly
"""

SAMPLE_ANNOUNCEMENTS = [
    {
        "tags": ["youth", "basketball", "meeting"],
        "input": "sa mga kabatan-onan nga gusto mo apil sa basketball adto sa court ugma alas 3",
        "output": "Sa mga kabatan-onan nga gustong moapil sa basketball, adto sa court ugma alas 3:00 sa hapon."
    },
    {
        "tags": ["meeting", "general"],
        "input": "naa miting ugma sa barangay hall alas 5 sa hapon ang tanan invited",
        "output": "Adunay miting ugma sa Barangay Hall alas 5:00 sa hapon. Ang tanan giawhag."
    },
    {
        "tags": ["health", "vaccination"],
        "input": "ang mga bata nga wala pa bakuna adto sa health center ugma buntag",
        "output": "Ang mga bata nga wala pa bakunaha, adto sa Health Center ugma sa buntag."
    },
    {
        "tags": ["cleaning", "schedule"],
        "input": "purok limpyo karong lunes ang matag panimalay maghimo",
        "output": "Purok limpyo karong Lunes. Ang matag panimalay gihangyo nga maghimo."
    },
    {
        "tags": ["distribution", "assistance"],
        "input": "naa ayuda ugma alas 9 sa buntag sa barangay hall ang mga qualified",
        "output": "Adunay ayuda ugma alas 9:00 sa buntag sa Barangay Hall para sa mga kwalipikado."
    },
    {
        "tags": ["registration", "documents"],
        "input": "municipal registrar naa sa barangay karong mercoles para sa libreng birth cert",
        "output": "Ang Municipal Registrar naa sa barangay karong Mercoles para sa libreng birth certificate."
    },
    {
        "tags": ["event", "fiesta"],
        "input": "pista sa cagbaoto sa sunod semana adto ang tanan aron moapil sa mga duwa",
        "output": "Pista sa Cagbaoto sa sunod semana. Adto ang tanan aron moapil sa mga dula."
    },
    {
        "tags": ["grammar", "correction"],
        "input": "sa mga kabatan-onan nga gusto mo apil sa liga adto sa gym ugma alas 3",
        "output": "Sa mga kabatan-onan nga gustong moapil sa liga, adto sa gym ugma alas 3:00 sa hapon."
    },
    {
        "tags": ["translation", "english", "clean-up"],
        "input": "there will be a clean up drive tomorrow 6am at purok 3 please bring broom and sacks",
        "output": "Pahibalo sa tanan nga adunay clean-up drive ugma alas 6 sa buntag sa Purok 3. Palihug dala og silhig ug mga sako."
    },
    {
        "tags": ["documents", "requirements", "list"],
        "input": "ang mga gusto mo kuha og indigency palihug dala birth certificate valid id ug proof nga taga cagbaoto ka",
        "output": "Ang mga gustong mokuha og indigency, palihug dala ang:\n1. Birth Certificate\n2. Valid ID\n3. Proof nga taga Cagbaoto ka"
    },
]

# Keywords for lightweight sample selection
SELECTION_KEYWORDS = [
    "basketball", "kabatan-onan", "youth", "club", "tournament",
    "tubig", "water", "disconnect", "putol", "service",
    "registrar", "birth", "marriage", "death", "certificate", "free",
    "optical", "eye", "medical", "health", "examination",
    "ZOD", "sanitary", "toilet", "evaluation", "inspection", "limpyo",
    "brigada", "eskwela", "school", "ginikanan", "parents", "volunteer",
    "business", "permit", "BOSS", "negosyante", "DTI", "mayor",
    "meeting", "panagtigom", "pahibalo", "announcement",
    "grammar", "correction", "translation", "english", "clean-up",
    "documents", "requirements", "list", "indigency", "dala"
]


def select_samples(raw_text: str, max_samples: int = 2) -> list[dict]:
    """
    Select the most relevant samples based on simple keyword matching.
    Returns at most max_samples samples with matching keywords.
    """
    text_lower = raw_text.lower()
    scored = []

    for sample in SAMPLE_ANNOUNCEMENTS:
        score = 0
        # Score based on tag matches
        for tag in sample.get("tags", []):
            if tag.lower() in text_lower:
                score += 2
        # Score based on keyword matches in input/output
        sample_text = (sample["input"] + " " + sample["output"]).lower()
        for keyword in SELECTION_KEYWORDS:
            if keyword in text_lower and keyword in sample_text:
                score += 1
        scored.append((score, sample))

    # Sort by score descending
    scored.sort(key=lambda x: x[0], reverse=True)
    
    # Return only samples with positive scores, at most max_samples
    return [sample for score, sample in scored[:max_samples] if score > 0]
