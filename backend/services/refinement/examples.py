"""
Examples database for Tandaganon Barangay announcements.

Grouped by announcement type with authentic Tandaganon dialect.
These examples follow the natural spoken style of Surigao del Sur Cebuano.
"""

# ============================================================================
# TANDAGANON DIALECT STYLE GUIDE FOR BARANGAY ANNOUNCEMENTS
# ============================================================================
#
# Tandaganon (Surigao del Sur Cebuano) is practical, direct, and resident-focused.
# This is NOT literary Cebuano. This is NOT Tagalog. This is local Surigao style.
#
# --- CORE PRINCIPLES ---
#
# 1. SHORT SENTENCES
#    - Maximum 15-20 words per sentence
#    - One idea per sentence
#    - Break complex ideas into multiple short sentences
#
# 2. DIRECT ADDRESS
#    - Speak TO residents, not ABOUT them
#    - "Sa tanang residente..." (To all residents...)
#    - Not "Ang mga residente gipahibalo..." (Residents are informed...)
#
# 3. ACTIVE VOICE
#    - "Nagpahibalo ang Barangay..." (The Barangay announces...)
#    - "Gitawag ang tanang..." (All are called...)
#    - Not passive or indirect constructions
#
# --- PREFERRED OPENINGS ---
#
# Standard announcement:
#   "Nagpahibalo ang Barangay..."
#   "Nagpahibalo ang Barangay sa tanang residente..."
#
# Direct address:
#   "Sa tanang residente sa Purok [X]..."
#   "Sa tanang ginikanan nga adunay anak nga nag-eskwela..."
#
# Reminder style:
#   "Pahimangno sa tanang [group]..."
#
# --- PREFERRED REMINDER PATTERNS ---
#
# Very common in Tandag/Surigao:
#   "Ayaw kalimti..." (Don't forget...)
#   "Ayaw hikalimti..." (Don't forget - stronger)
#   "Hinumdomi..." (Remember...)
#   "Palihog..." (Please...)
#
# --- PREFERRED CLOSING PATTERNS ---
#
# Standard close:
#   "Daghang salamat"
#
# With gratitude:
#   "Salamat sa inyong pagpakabana"
#   "Salamat sa inyong kooperasyon"
#
# Simple, no elaborate sign-offs
#
# --- WORD CHOICES (Tandaganon vs Generic Cebuano) ---
#
# USE THESE (Tandaganon/Surigao style):
#   "kay" for because (in quick announcements, not "tungod kay")
#   "aron" for purpose/so that
#   "didto" for location (not "diha" in formal announcements)
#   "karon" / "karong" for current time
#   "umaabot" for upcoming
#   "hangtod" for until/deadline
#   "alang sa" for for the purpose of
#
# AVOID THESE (Too formal/literary):
#   "tungod kay" (too wordy)
#   "agig" (too formal)
#   "tungod sa" (government memo style)
#
# --- PHRASES TO AVOID (Will trigger validation failure) ---
#
# Literary Cebuano (too deep/formal):
#   "Pinaagi niini..."
#   "Pinangga namong..."
#   "Gihigugma namo..."
#   "Dungog ug pasidungog..."
#   "Minahal naming..."
#
# Tagalog-influenced:
#   "Ginagawa namin..."
#   "Aming inihahatid..."
#   "Kami po ay..."
#   "Ipinapaalam..."
#   "Ipinabatid..."
#   "Nagpapasalamat..."
#
# Government memo style:
#   "Mga kabarangay..."
#   "Mga minamahal..."
#   "Ka naming..."
#   "Mga ginigiyahan..."
#
# --- SENTENCE STRUCTURE EXAMPLES ---
#
# GOOD (Direct, simple):
#   "Nagpahibalo ang Barangay. Adunay miting karung Martes sa alas 3:00 sa hapon."
#   "Gitawag ang tanang residente sa pagtambong."
#   "Ayaw kalimti ang pagdala og ID."
#
# BAD (Complex, indirect):
#   "Pinaagi niini ginapahibalo sa tanan nga adunay miting nga ipahigayon..."
#   "Gipahibalo sa Barangay nga ang tanang residente gitawag sa pagtambong..."
#
# --- PRACTICAL TONE CHECKLIST ---
#
# Does it sound like a Barangay staff member explaining to neighbors?
# Can a typical resident understand it on first reading?
# Is it free of flowery or academic language?
# Are sentences short and clear?
# Is the most important information first?
#
# ============================================================================

# Authentic Tandaganon examples grouped by type
EXAMPLES = {
    "meeting_notice": [
        {
            "draft": "Miting sa purok 5 sa martes alas 3 sa hapon",
            "refined": "Nagpahibalo ang Barangay sa tanang residente sa Purok 5. Adunay miting karung Martes sa alas 3:00 sa hapon sa Session Hall. Gitawag ang tanang opisyales ug volunteer sa pagtambong aron hisgotan ang kalihukan sa sunod bulan."
        },
        {
            "draft": "Mga parents meeting sa eskwelahan sa lunes",
            "refined": "Sa tanang ginikanan nga adunay anak nga nag-eskwela. Meeting karung Lunes sa alas 8:00 sa buntag didto sa eskwelahan. Gikinahanglan ang inyong pagtambong aron hisgotan ang bag-ong tuig nga pasar-on."
        }
    ],
    "community_event": [
        {
            "draft": "Sportsfest sa barangay karung biernes",
            "refined": "Nagpahibalo ang Barangay. Magpahigayon og Sportsfest karung Biyernes sa alas 6:00 sa hapon sa Covered Court. Gitawag ang tanang kabatan-onan sa pag-apil sa basketball, volleyball, ug badminton."
        },
        {
            "draft": "Disco sa plaza sa sabado gabii",
            "refined": "Nagpahibalo ang Sangguniang Kabataan. Adunay disco karung Sabado sa gabii alas 8:00 sa plaza. Kinahanglan ang inyong pagsulod ug pagtambong alang sa fundraising sa sports equipment."
        }
    ],
    "clean_up_drive": [
        {
            "draft": "Brigada eskwela sa hunyo 10-14",
            "refined": "Nagpahibalo ang Barangay. Ang Brigada Eskwela ipahigayon sa Hunyo 10 hangtod 14, 2025. Gitawag ang tanang ginikanan, estudyante, ug miyembro sa komunidad sa pagtambong aron paghinlo sa tunghaan. Magdala og silhig, sako, ug gamit panglinis. Ang opening parade sa Hunyo 10 sa alas 6:00 sa buntag."
        },
        {
            "draft": "Clean up sa kalsada sa purok 3 ugma",
            "refined": "Nagpahibalo ang Barangay sa tanang residente sa Purok 3. Adunay clean-up drive karung umaabot nga Sabado sa alas 6:00 sa buntag. Kinahanglan ang pag-apil sa matag panimalay aron paghinlo sa atong mga kalsada ug kanal."
        }
    ],
    "health_advisory": [
        {
            "draft": "Libreng bakuna sa barangay hall sa hwebes",
            "refined": "Nagpahibalo ang Municipal Health Office ug Barangay Health Center. Adunay libreng bakuna karung Huwebes sa alas 8:00 sa buntag sa Barangay Hall. Gitawag ang tanang senior citizen, mga bata, ug ginikanan sa pagdala sa mga bata para sa routine vaccination."
        },
        {
            "draft": "Medical mission sa covered court lunes ug martes",
            "refined": "Nagpahibalo ang Barangay. Adunay libreng medical mission karung Lunes ug Martes sa alas 8:00 sa buntag sa Covered Court. Adunay libreng check-up, blood pressure monitoring, ug hatag sa maintenance medicines alang sa mga senior ug PWD."
        }
    ],
    "government_service": [
        {
            "draft": "Business permit sa barangay karung bulan",
            "refined": "Nagpahibalo ang Barangay sa tanang negosyante. Ang pagkuha sa Barangay Business Permit ipahigayon karung tibuok bulan. Kinahanglan magdala og valid ID, Cedula, ug Purok Clearance. Ang opisina abli sa Lunes hangtod Biyernes sa alas 8:00 sa buntag hangtod 5:00 sa hapon."
        },
        {
            "draft": "RSBSA registration sa mga mag-uuma",
            "refined": "Nagpahibalo ang Municipal Agriculture Office ug Barangay. Ang RSBSA registration alang sa mga mag-uuma ug mangingisda ipahigayon karung Lunes sa alas 9:00 sa buntag sa Barangay Hall. Kinahanglan magdala og valid ID ug proof of farming o fishing activities."
        }
    ],
    "emergency_notice": [
        {
            "draft": "Brownout sa kuryente sa martes ug hwebes",
            "refined": "Nagpahibalo ang Barangay sa tanang residente. Adunay brownout sa kuryente karung Martes ug Huwebes sa alas 9:00 sa buntag hangtod 4:00 sa hapon kay mag-ayo sa power lines. Palihog pag-una sa mga importanteng gamit nga gikinahanglan og kuryente."
        },
        {
            "draft": "Pagputol sa tubig sa barangay karung sabado",
            "refined": "Nagpahibalo ang Barangay sa tanang residente. Magpahigayon og pagputol sa tubig karung Sabado sa alas 8:00 sa buntag hangtod 5:00 sa hapon kay mag-ayo sa main pipeline. Ayaw kalimti ang pagtipid sa tubig ug pag-una sa balde ug tanke sa dili pa ang schedule."
        }
    ],
    "reminder_deadline": [
        {
            "draft": "Last day sa pagbayad sa tax karung marso 15",
            "refined": "Pahimangno sa tanang residente. Ang deadline sa pagbayad sa Community Tax Certificate (Cedula) karung Marso 15, 2025. Ang opisina abli sa Lunes hangtod Biyernes sa alas 8:00 sa buntag hangtod 5:00 sa hapon. Ayaw kalimti ang petsa."
        },
        {
            "draft": "Hangtod karung friday lang ang pagparehistro sa 4ps",
            "refined": "Pahimangno sa tanang benepesyaryo sa 4Ps. Hangtod Biyernes lang ang pag-update sa inyong profiling. Ang Municipal Link mag-atubang sa Barangay Hall sa alas 9:00 sa buntag. Ayaw kalimti ang inyong QR code ug valid ID."
        }
    ],
    "general_announcement": [
        {
            "draft": "Bag-ong barangay tanod nga si Juan Cruz",
            "refined": "Nagpahibalo ang Barangay. Ang bag-ong Barangay Tanod nga si Juan Cruz ang mag-duty sa gabii sa Purok 2 ug Purok 3. Para sa emerhensiya, matawag siya sa Barangay Hall o direktang tawag sa barangay hotline number."
        },
        {
            "draft": "Nagpasalamat ang barangay sa mga sponsor sa fiesta",
            "refined": "Nagpasalamat ang Barangay Council ug tanang opisyales sa mga sponsor ug donators sa malampusong Barangay Fiesta. Ang inyong suporta dakong tabang sa kalampuson sa atong mga kalihukan. Daghang salamat sa pagpakabana."
        }
    ]
}

# Keywords for rule-based classification
# NOTE: Keywords are weighted by length in classifier - longer = more specific = higher score
CLASSIFICATION_KEYWORDS = {
    "meeting_notice": [
        # High-weight specific meeting terms (priority detection)
        "panagtigom", "panag tigum", "barangay hall",
        # Standard meeting terms
        "miting", "meeting", "tambong", "pulong", "conference",
        "discussion", "hisgot", "agenda", "minutes", "assembly",
        "pulong-pulong", "tigum"
    ],
    "community_event": [
        "fiesta", "sportsfest", "disco", "programa", "celebration",
        "party", "contest", "competition", "pageant", "bayle",
        "sayaw", "kanta", "laro", "games"
    ],
    "clean_up_drive": [
        "brigada", "clean", "linis", "hugaw", "basura",
        "kalimpyo", "clean-up", "drive", "sweep", "silhig",
        "tanom", "tree planting", "environment", "kalikasan"
    ],
    "health_advisory": [
        "bakuna", "vaccine", "check-up", "medical", "health",
        "medicine", "doctor", "nurse", "checkup", "libre",
        "free", "dengue", "covid", "flu", "diseases"
    ],
    "government_service": [
        "permit", "clearance", "cedula", "rsbsa", "registration",
        "business", "4ps", "indigent", "senior", "pwd",
        "soloparent", "solo parent", "id", "document"
    ],
    "emergency_notice": [
        "brownout", "blackout", "kuryente", "tubig", "water",
        "emergency", "alert", "warning", "delikado", "baha",
        "sunog", "fire", "typhoon", "bagyo", "evacuate"
    ],
    "reminder_deadline": [
        "deadline", "last day", "hangtod", "reminder", "pahimangno",
        "warning", "ultimatum", "due date", "payment", "bayad",
        "mohunong", "mohuman", "takdang panahon"
    ],
    "general_announcement": [
        "pahibalo", "announcement", "pasalamat", "thank you",
        "congratulations", "congrats", "welcome", "bag-ong opisyal",
        "new tanod", "recognition"
    ]
}

# ============================================================================
# POSITIVE DIALECT REFERENCE - USABLE BY PROMPTS AND VALIDATOR
# ============================================================================

TANDAGANON_PATTERNS = {
    "preferred_openings": [
        "Nagpahibalo ang Barangay",
        "Sa tanang residente",
        "Sa mga residente",
        "Pahibalo alang sa tanang",
        "Nagpasabot ang Barangay",
    ],
    "preferred_reminders": [
        "Ayaw kalimti",
        "Hinumdomi",
        "Palihog dala",
        "Ayaw hikalimti",
    ],
    "preferred_closings": [
        "Daghang salamat",
        "Salamat sa inyong pagpakabana",
    ],
    "preferred_calls": [
        "Gitawag",
        "Giawhag",
        "Gihangyo",
    ],
    "preferred_requirements": [
        "Kinahanglan",
        "Gikinahanglan",
    ],
    "practical_connectors": [
        "kay",
        "aron",
        "kay para",
    ],
    "time_markers": [
        "karon",
        "karong",
        "umaabot",
        "karung buntaga",
        "karung hapon",
    ],
    "local_flavor": [
        "alang sa kaayohan",
        "para sa tanan",
        "sa barangay",
        "didto sa",
    ],
}

PHRASES_TO_AVOID = {
    "literary_cebuano": [
        "pinaagi niini",
        "pinangga namo",
        "pinangga namong",
        "gihigugma namo",
        "dungog ug pasidungog",
    ],
    "tagalog_influenced": [
        "ginagawa namin",
        "aming inihahatid",
        "kami po ay",
        "ipinapaalam",
        "ipinabatid",
        "nagpapasalamat",
    ],
    "formal_government": [
        "mga kabarangay",
        "mga minamahal",
        "ka naming",
        "mga ginigiyahan",
    ],
    "overly_complex": [
        "tungod kay",
        "sa kadugayan",
        "sa pagsugod",
    ],
}

# Scoring weights for validator
POSITIVE_PATTERN_WEIGHTS = {
    "preferred_openings": 2.0,
    "preferred_reminders": 1.5,
    "preferred_calls": 1.0,
    "practical_connectors": 0.5,
    "time_markers": 0.5,
    "local_flavor": 0.5,
}


def get_examples_for_type(announcement_type: str, max_examples: int = 2) -> list:
    """
    Get relevant examples for a specific announcement type.
    
    Args:
        announcement_type: The type of announcement
        max_examples: Maximum number of examples to return
        
    Returns:
        List of example dictionaries with 'draft' and 'refined' keys
    """
    examples = EXAMPLES.get(announcement_type, [])
    if not examples:
        # Fallback to general_announcement if type not found
        examples = EXAMPLES.get("general_announcement", [])
    
    return examples[:max_examples]


def get_classification_keywords() -> dict:
    """
    Get the keyword mapping for classification.
    
    Returns:
        Dictionary mapping announcement types to keyword lists
    """
    return CLASSIFICATION_KEYWORDS.copy()


def get_tandaganon_patterns() -> dict:
    """
    Get the structured Tandaganon dialect patterns for prompts and validation.
    
    Returns:
        Dictionary with preferred patterns, phrases to avoid, and scoring weights
    """
    return {
        "preferred": TANDAGANON_PATTERNS,
        "avoid": PHRASES_TO_AVOID,
        "weights": POSITIVE_PATTERN_WEIGHTS,
    }


def format_patterns_for_prompt() -> str:
    """
    Format the Tandaganon patterns as a string suitable for inclusion in prompts.
    
    Returns:
        Formatted string with preferred patterns and phrases to avoid
    """
    lines = ["\nTANDAGANON DIALECT PATTERNS (MUST USE THESE):", ""]
    
    for category, patterns in TANDAGANON_PATTERNS.items():
        if patterns:
            lines.append(f"  {category.replace('_', ' ').title()}:")
            for pattern in patterns[:5]:  # Limit to first 5 per category
                lines.append(f"    - \"{pattern}\"")
    
    lines.extend(["", "PHRASES TO AVOID (DO NOT USE):", ""])
    
    for category, phrases in PHRASES_TO_AVOID.items():
        if phrases:
            lines.append(f"  {category.replace('_', ' ').title()}:")
            for phrase in phrases[:3]:  # Limit to first 3 per category
                lines.append(f"    - \"{phrase}\"")
    
    return "\n".join(lines)
