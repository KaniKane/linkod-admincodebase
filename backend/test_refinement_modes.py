"""
Test script for LINKod AI refinement pipeline.
Tests adaptive modes: short, medium, and long inputs.
"""

import sys
sys.path.insert(0, 'd:/GitHub/linkod_admin/linkod-admincodebase/backend')

from services.refinement.refinement_service import refine_text_pipeline
from services.refinement.prompt_builder import get_mode_for_logging, build_refinement_prompt
from services.refinement.entity_extractor import extract_protected_facts

# Test samples
SHORT_SAMPLES = [
    "miting sa martes alas 3",
    "Linis sa kalsada ugma",
    "panagtigom sa barangay hall lunis",
]

LONG_SAMPLES = [
    """Nagpahibalo ang Barangay sa tanang residente sa Purok 4. 
Adunay emergency meeting karung Lunes sa alas 5:00 sa hapon sa Barangay Hall. 
Gitawag ang tanang opisyales ug mga volunteer sa pagtambong aron hisgotan ang pag-ayo sa mga drainage system 
ug paglimpyo sa mga kanal sa atong lugar. Kinahanglan ang inyong presensya ug pakig-uban 
aron masulbad ang problema sa baha sa panahon sa kusog nga ulan. Palihog dala og ID sa pag-sign in.""",
    
    """Sa tanang ginikanan nga adunay anak nga nag-eskwela sa Barangay Elementary School. 
Nagpahibalo ang eskwelahan nga adunay Brigada Eskwela karung Hunyo 10 hangtod 14, 2025. 
Gitawag ang tanang ginikanan, estudyante, ug mga boluntaryo sa pagtambong aron paghinlo sa mga classroom 
ug pag-ayo sa mga broken facilities. Magdala og silhig, sako, ug uban pang gamit panglinis. 
Ang opening parade sa Hunyo 10 sa alas 6:00 sa buntag. Ayaw kalimti ang inyong pag-apil.""",
]

def test_mode_detection():
    """Test that mode detection works correctly."""
    print("=" * 60)
    print("TEST 1: MODE DETECTION")
    print("=" * 60)
    
    for sample in SHORT_SAMPLES:
        mode = get_mode_for_logging(sample)
        word_count = len(sample.split())
        print(f"  Input ({word_count} words): '{sample[:50]}...' -> Mode: {mode}")
    
    for sample in LONG_SAMPLES:
        mode = get_mode_for_logging(sample)
        word_count = len(sample.split())
        print(f"  Input ({word_count} words): '{sample[:50]}...' -> Mode: {mode}")
    
    print()

def test_prompt_building():
    """Test that prompts are built correctly for each mode."""
    print("=" * 60)
    print("TEST 2: PROMPT BUILDING & SIZE CHECK")
    print("=" * 60)
    
    # Test short
    for sample in SHORT_SAMPLES[:1]:
        mode = get_mode_for_logging(sample)
        facts = extract_protected_facts(sample)
        prompt = build_refinement_prompt(sample, "meeting_notice", facts)
        print(f"\n  SHORT MODE:")
        print(f"    Input: '{sample}'")
        print(f"    Mode: {mode}")
        print(f"    Prompt length: {len(prompt)} chars")
        print(f"    Prompt lines: {len(prompt.split(chr(10)))}")
        print(f"    Expected: <500 chars")
        print(f"    Status: {'PASS' if len(prompt) < 500 else 'FAIL - TOO LARGE'}")
    
    # Test long
    for sample in LONG_SAMPLES[:1]:
        mode = get_mode_for_logging(sample)
        facts = extract_protected_facts(sample)
        prompt = build_refinement_prompt(sample, "meeting_notice", facts)
        print(f"\n  LONG MODE:")
        print(f"    Input: '{sample[:60]}...'")
        print(f"    Mode: {mode}")
        print(f"    Word count: {len(sample.split())}")
        print(f"    Prompt length: {len(prompt)} chars")
        print(f"    Prompt lines: {len(prompt.split(chr(10)))}")
        print(f"    Expected: <2000 chars")
        print(f"    Status: {'PASS' if len(prompt) < 2000 else 'FAIL - TOO LARGE'}")
    
    print()

def test_refinement_pipeline():
    """Test the full refinement pipeline (requires Ollama running)."""
    print("=" * 60)
    print("TEST 3: FULL REFINEMENT PIPELINE")
    print("=" * 60)
    print("  NOTE: This requires Ollama to be running with llama3.2:3b")
    print()
    
    # Test short
    sample = SHORT_SAMPLES[0]
    print(f"  Testing SHORT input: '{sample}'")
    print(f"  Mode: {get_mode_for_logging(sample)}")
    print()
    
    try:
        result = refine_text_pipeline(sample, enable_logging=True, max_retries=0)
        
        print(f"  Result:")
        print(f"    Original: {result['original_text']}")
        print(f"    Refined:  {result['refined_text']}")
        print(f"    Mode:     {result.get('metadata', {}).get('mode', 'unknown')}")
        print(f"    Prompt:   {result.get('metadata', {}).get('prompt_length', 0)} chars")
        print(f"    Gen Time: {result.get('metadata', {}).get('generation_time_ms', 0)} ms")
        print(f"    Fallback: {result.get('fallback_used', False)}")
        
        if result.get('warnings'):
            print(f"    Warnings: {result['warnings']}")
        
        print()
    except Exception as e:
        print(f"  ERROR: {e}")
        print("  Make sure Ollama is running with 'ollama run llama3.2:3b'")
        print()
    
    # Test long
    sample = LONG_SAMPLES[0]
    print(f"  Testing LONG input: '{sample[:50]}...'")
    print(f"  Mode: {get_mode_for_logging(sample)}")
    print()
    
    try:
        result = refine_text_pipeline(sample, enable_logging=True, max_retries=0)
        
        print(f"  Result:")
        print(f"    Original: {result['original_text'][:60]}...")
        print(f"    Refined:  {result['refined_text'][:60]}...")
        print(f"    Mode:     {result.get('metadata', {}).get('mode', 'unknown')}")
        print(f"    Prompt:   {result.get('metadata', {}).get('prompt_length', 0)} chars")
        print(f"    Gen Time: {result.get('metadata', {}).get('generation_time_ms', 0)} ms")
        print(f"    Fallback: {result.get('fallback_used', False)}")
        
        if result.get('warnings'):
            print(f"    Warnings: {result['warnings']}")
        
        print()
    except Exception as e:
        print(f"  ERROR: {e}")
        print("  Make sure Ollama is running with 'ollama run llama3.2:3b'")
        print()

def show_prompt_structure():
    """Show the structure of prompts for each mode."""
    print("=" * 60)
    print("TEST 4: PROMPT STRUCTURE VISUALIZATION")
    print("=" * 60)
    
    # Short
    sample = "miting sa martes alas 3"
    facts = extract_protected_facts(sample)
    prompt = build_refinement_prompt(sample, "meeting_notice", facts)
    
    print(f"\n  SHORT MODE PROMPT ({len(prompt)} chars):")
    print("  " + "-" * 50)
    lines = prompt.split(chr(10))
    for i, line in enumerate(lines[:15]):  # Show first 15 lines
        print(f"  {i+1:2}: {line[:50]}")
    if len(lines) > 15:
        print(f"  ... ({len(lines)-15} more lines)")
    print()
    
    # Long sample (first 100 chars)
    sample = LONG_SAMPLES[0][:100]
    facts = extract_protected_facts(sample)
    prompt = build_refinement_prompt(sample, "meeting_notice", facts)
    
    print(f"\n  LONG MODE PROMPT ({len(prompt)} chars):")
    print("  " + "-" * 50)
    lines = prompt.split(chr(10))
    for i, line in enumerate(lines[:15]):  # Show first 15 lines
        print(f"  {i+1:2}: {line[:50]}")
    if len(lines) > 15:
        print(f"  ... ({len(lines)-15} more lines)")
    print()

if __name__ == "__main__":
    print("\n" + "=" * 60)
    print("LINKOD AI REFINEMENT - ADAPTIVE MODES TEST")
    print("=" * 60)
    print()
    
    # Run tests
    test_mode_detection()
    test_prompt_building()
    show_prompt_structure()
    test_refinement_pipeline()
    
    print("=" * 60)
    print("TEST COMPLETE")
    print("=" * 60)
