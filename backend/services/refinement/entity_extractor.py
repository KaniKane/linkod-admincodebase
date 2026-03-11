"""
Entity extractor for the refinement pipeline.

Extracts protected facts (dates, times, locations, names, numbers) using regex
and simple parsing. These facts must be preserved in the refined output.
"""

import re
from typing import Dict, List, Any


def extract_protected_facts(text: str) -> Dict[str, List[str]]:
    """
    Extract protected facts from the input text.
    
    Args:
        text: The announcement text to analyze
        
    Returns:
        Dictionary with keys: dates, times, locations, names, numbers
    """
    if not text or not text.strip():
        return {"dates": [], "times": [], "locations": [], "names": [], "numbers": []}
    
    return {
        "dates": _extract_dates(text),
        "times": _extract_times(text),
        "locations": _extract_locations(text),
        "names": _extract_names(text),
        "numbers": _extract_numbers(text)
    }


def _extract_dates(text: str) -> List[str]:
    """Extract dates in various formats including Tandaganon relative dates."""
    dates = []
    
    # Common date patterns
    patterns = [
        # Month Day, Year (e.g., "January 15, 2025" or "Enero 15, 2025")
        r'\b(?:January|February|March|April|May|June|July|August|September|October|November|December|Enero|Pebrero|Marso|Abril|Mayo|Hunyo|Hulyo|Agosto|Septiyembre|Oktubre|Nobyembre|Disyembre)\s+\d{1,2}(?:,\s+\d{4})?\b',
        
        # Day Month Year (e.g., "15 January 2025")
        r'\b\d{1,2}\s+(?:January|February|March|April|May|June|July|August|September|October|November|December|Enero|Pebrero|Marso|Abril|Mayo|Hunyo|Hulyo|Agosto|Septiyembre|Oktubre|Nobyembre|Disyembre)(?:\s+\d{4})?\b',
        
        # Numeric dates (e.g., "01/15/2025", "2025-01-15")
        r'\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b',
        r'\b\d{4}[/-]\d{1,2}[/-]\d{1,2}\b',
        
        # Day names with dates (e.g., "Lunes, Enero 15")
        r'\b(?:Lunes|Martes|Miyerkules|Huwebes|Biyernes|Sabado|Linggo|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)(?:,\s+(?:sa\s+)?(?:\d{1,2}|\w+\s+\d{1,2}))?\b',
        
        # Relative dates (Tandaganon/Surigao del Sur specific)
        r'\b(?:karong|karon|karun)\s+(?:Lunes|Martes|Miyerkules|Huwebes|Biyernes|Sabado|Linggo)\b',
        r'\b(?:karong|karon|karun)\s+(?:Enero|Pebrero|Marso|Abril|Mayo|Hunyo|Hulyo|Agosto|Septiyembre|Oktubre|Nobyembre|Disyembre)\b',
        r'\bumaabot\s+(?:nga\s+)?(?:Lunes|Martes|Miyerkules|Huwebes|Biyernes|Sabado|Linggo)\b',
        r'\b(?:ngadtong|adtong)\s+(?:Lunes|Martes|Miyerkules|Huwebes|Biyernes|Sabado|Linggo)\b',
        
        # Relative time markers (ugma, karon, gahapon, etc.)
        r'\b(?:ugma|karon|karong adlawa|gahapon|gahapun)\b',
        
        # Date ranges (e.g., "Hunyo 10-14", "June 10-14")
        r'\b(?:January|February|March|April|May|June|July|August|September|October|November|December|Enero|Pebrero|Marso|Abril|Mayo|Hunyo|Hulyo|Agosto|Septiyembre|Oktubre|Nobyembre|Disyembre)\s+\d{1,2}(?:-|hangtod\s+|\s+hangtod\s+)\d{1,2}(?:,\s+\d{4})?\b',
        
        # Year alone
        r'\b(?:20)\d{2}\b',
    ]
    
    for pattern in patterns:
        matches = re.findall(pattern, text, re.IGNORECASE)
        dates.extend(matches)
    
    # Remove duplicates while preserving order
    seen = set()
    unique_dates = []
    for d in dates:
        d_lower = d.lower()
        if d_lower not in seen:
            seen.add(d_lower)
            unique_dates.append(d)
    
    return unique_dates


def _extract_times(text: str) -> List[str]:
    """Extract time expressions."""
    times = []
    
    patterns = [
        # Standard time with AM/PM (e.g., "3:00 PM", "3:00pm", "alas 3:00 sa hapon")
        r'\b(?:alas\s+)?\d{1,2}(?::\d{2})?\s*(?:sa\s+)?(?:buntag|udto|hapon|gabii|buntag|am|pm|AM|PM|a\.m\.|p\.m\.)\b',
        
        # Time ranges (e.g., "8:00 sa buntag - 5:00 sa hapon")
        r'\b(?:alas\s+)?\d{1,2}(?::\d{2})?\s*(?:sa\s+)?(?:buntag|udto|hapon|gabii)\s*(?:-|hangtod|to)\s*(?:alas\s+)?\d{1,2}(?::\d{2})?\s*(?:sa\s+)?(?:buntag|udto|hapon|gabii)\b',
        
        # Simple time (e.g., "alas 3", "3:00", "3pm", "3PM")
        r'\b(?:alas\s+)?\d{1,2}:\d{2}\b',
        r'\balas\s+\d{1,2}(?:\s+sa\s+(?:buntag|udto|hapon|gabii))?\b',
        
        # NEW: Time with attached AM/PM like "3pm", "4PM", "5:30am"
        r'\b\d{1,2}(?::\d{2})?(?:am|pm|AM|PM)\b',
        
        # NEW: Time with space before AM/PM like "3 pm", "4 PM"
        r'\b\d{1,2}(?::\d{2})?\s*(?:am|pm|AM|PM)\b',
        
        # Duration (e.g., "2 ka oras", "duha ka oras")
        r'\b(?:\d+|duha|tulo|upat|lima|unom|pito|walo|siyam|napu)\s+ka\s+oras\b',
    ]
    
    for pattern in patterns:
        matches = re.findall(pattern, text, re.IGNORECASE)
        times.extend(matches)
    
    # Remove duplicates while preserving order
    seen = set()
    unique_times = []
    for t in times:
        t_clean = t.lower().strip().replace(' ', '')
        if t_clean not in seen:
            seen.add(t_clean)
            unique_times.append(t)
    
    return unique_times


def _extract_locations(text: str) -> List[str]:
    """Extract location references."""
    locations = []
    
    patterns = [
        # Purok references
        r'\b(?:sa\s+)?Purok\s+\d+\b',
        r'\b(?:sa\s+)?Sitio\s+\w+\b',
        
        # Barangay facilities
        r'\b(?:Barangay\s+)?(?:Hall|Session Hall|Covered Court|Plaza|Health Center|Outpost|Multi-Purpose Hall)\b',
        
        # Common locations
        r'\b(?:sa\s+)?(?:Elementary School|High School|Day Care|Daycare)\b',
        r'\b(?:sa\s+)?(?:Covered Court|Basketball Court|Plaza|Church|Simbahan|Capilya)\b',
        
        # Barangay name mentions (e.g., "Barangay San Isidro", "sa Barangay")
        r'\bBarangay\s+(?:[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\b',
        
        # Street/Road references
        r'\b(?:National Road|Provincial Road|Barangay Road|kalsada|dalan)\b',
        
        # Building references
        r'\b(?:Municipal Hall|Munisipyo|City Hall|Health Office|Agriculture Office)\b',
    ]
    
    for pattern in patterns:
        matches = re.findall(pattern, text, re.IGNORECASE)
        locations.extend(matches)
    
    # Also look for "sa/diha sa/didto sa X" patterns
    sa_pattern = r'\b(?:sa|diha\s+sa|didto\s+sa)\s+([A-Z][a-zA-Z\s]+?)(?:\.|,|nga|ang|$)'
    sa_matches = re.findall(sa_pattern, text)
    for match in sa_matches:
        match_clean = match.strip()
        if len(match_clean) > 2 and len(match_clean) < 50:
            locations.append(f"sa {match_clean}")
    
    # Remove duplicates while preserving order
    seen = set()
    unique_locations = []
    for loc in locations:
        loc_lower = loc.lower()
        if loc_lower not in seen:
            seen.add(loc_lower)
            unique_locations.append(loc)
    
    return unique_locations


def _extract_names(text: str) -> List[str]:
    """Extract person names (best effort)."""
    names = []
    
    # Look for "si X" or "kang X" patterns (Cebuano name markers)
    patterns = [
        r'\b(?:si|kang|gikan\s+kang)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\b',
        r'\b(?:Hon\.|Hon|HON)\.?\s+([A-Z][a-z]+(?:\s+[A-Z\.?][a-z]+)*)\b',
        r'\b(?:Kapitan|Kagawad|Tanod|Secretary|Treasurer)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\b',
        r'\b(?:Kap\.|Kag\.)\s+([A-Z][a-z]+)\b',
    ]
    
    for pattern in patterns:
        matches = re.findall(pattern, text)
        if isinstance(matches, list) and matches:
            if isinstance(matches[0], tuple):
                matches = [m[0] for m in matches if m]
            names.extend(matches)
    
    # Remove common false positives
    false_positives = {
        'Barangay', 'Purok', 'Sitio', 'The', 'This', 'That', 'Municipal',
        'City', 'Provincial', 'National', 'January', 'February', 'March',
        'April', 'May', 'June', 'July', 'August', 'September', 'October',
        'November', 'December', 'Enero', 'Pebrero', 'Marso', 'Abril',
        'Mayo', 'Hunyo', 'Hulyo', 'Agosto', 'Septiyembre', 'Oktubre',
        'Nobyembre', 'Disyembre'
    }
    
    filtered_names = [n for n in names if n not in false_positives]
    
    # Remove duplicates while preserving order
    seen = set()
    unique_names = []
    for name in filtered_names:
        name_lower = name.lower()
        if name_lower not in seen:
            seen.add(name_lower)
            unique_names.append(name)
    
    return unique_names


def _extract_numbers(text: str) -> List[str]:
    """Extract numerical values (amounts, contact numbers, etc.)."""
    numbers = []
    
    patterns = [
        # Phone numbers (Philippine format)
        r'\b(?:09\d{9}|\+63\d{10}|0\d{8,10})\b',
        
        # Amounts with currency
        r'\b(?:Php|P|PhP|₱)\s*\d+(?:,\d{3})*(?:\.\d{2})?\b',
        r'\b\d+(?:,\d{3})*(?:\.\d{2})?\s*(?:pesos|peso)\b',
        
        # Simple amounts
        r'\b(?:\d+|\d{1,3}(?:,\d{3})+)\s*(?:ka\s+buok|ka\s+items?|pcs?|pieces?)\b',
        
        # Numbers with units
        r'\b\d+\s*(?:years?|months?|days?|hours?|minutes?|meter|km|kilometer)\b',
        
        # Percentage
        r'\b\d+(?:\.\d+)?%\b',
        
        # Counts with Cebuano numbers
        r'\b(?:usa|duha|tulo|upat|lima|unom|pito|walo|siyam|napu)\s+ka\s+\w+\b',
    ]
    
    for pattern in patterns:
        matches = re.findall(pattern, text, re.IGNORECASE)
        numbers.extend(matches)
    
    # Also capture standalone numbers that look significant
    significant_numbers = re.findall(r'\b(?!20\d{2}\b)\d{3,}(?:\.\d+)?\b', text)
    numbers.extend(significant_numbers)
    
    # Remove duplicates while preserving order
    seen = set()
    unique_numbers = []
    for num in numbers:
        num_lower = num.lower()
        if num_lower not in seen:
            seen.add(num_lower)
            unique_numbers.append(num)
    
    return unique_numbers


def format_facts_for_prompt(facts: Dict[str, List[str]]) -> str:
    """
    Format extracted facts for inclusion in a prompt.
    
    Args:
        facts: Dictionary of extracted facts
        
    Returns:
        Formatted string for prompt insertion
    """
    lines = []
    
    if facts.get("dates"):
        lines.append(f"Dates: {', '.join(facts['dates'])}")
    if facts.get("times"):
        lines.append(f"Times: {', '.join(facts['times'])}")
    if facts.get("locations"):
        lines.append(f"Locations: {', '.join(facts['locations'])}")
    if facts.get("names"):
        lines.append(f"Names: {', '.join(facts['names'])}")
    if facts.get("numbers"):
        lines.append(f"Numbers/Amounts: {', '.join(facts['numbers'])}")
    
    if not lines:
        return "(No specific protected facts detected - preserve all information from draft)"
    
    return "\n".join(lines)


def verify_facts_preserved(original_facts: Dict[str, List[str]], refined_text: str) -> Dict[str, Any]:
    """
    Check if protected facts from the original are present in the refined text.
    
    Args:
        original_facts: Facts extracted from original text
        refined_text: The refined announcement text
        
    Returns:
        Dictionary with 'all_preserved' (bool) and 'missing' (list of missing facts)
    """
    refined_lower = refined_text.lower()
    missing = []
    
    # Check each category
    for category, facts in original_facts.items():
        for fact in facts:
            # Normalize fact for comparison
            fact_normalized = fact.lower().strip()
            
            # Check if fact appears in refined text (with some flexibility)
            # For dates, check if core components appear
            if category == "dates":
                # Extract day and month for flexible matching
                day_match = re.search(r'\d{1,2}', fact)
                if day_match:
                    day = day_match.group()
                    # Check if day appears in refined
                    if day not in refined_text:
                        missing.append(f"{category}: {fact}")
                        continue
            
            # For other facts, check exact or near-match
            if fact_normalized not in refined_lower:
                # Try partial match for longer facts
                if len(fact_normalized) > 5:
                    words = fact_normalized.split()
                    if len(words) > 1:
                        # Check if majority of words appear
                        matches = sum(1 for word in words if word in refined_lower)
                        if matches < len(words) * 0.5:  # Less than 50% match
                            missing.append(f"{category}: {fact}")
                    else:
                        missing.append(f"{category}: {fact}")
                else:
                    missing.append(f"{category}: {fact}")
    
    return {
        "all_preserved": len(missing) == 0,
        "missing": missing
    }
