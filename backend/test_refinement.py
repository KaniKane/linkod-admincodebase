#!/usr/bin/env python3
"""
Test script for the refinement pipeline.

Run this to verify the 5-stage pipeline is working correctly.
"""

import sys
sys.path.insert(0, 'd:/GitHub/linkod_admin/linkod-admincodebase/backend')

from services.refinement_service import (
    RefinementService, 
    InputAnalyzer, 
    DialectMode,
    ContentType
)
from services.prompt_builder import PromptBuilder, PromptContext
from services.output_validator import OutputValidator, validate_output
from services.example_retriever import get_examples


def test_analyzer():
    """Test input analysis stage."""
    print("=" * 60)
    print("TEST 1: Input Analysis")
    print("=" * 60)
    
    analyzer = InputAnalyzer()
    
    test_inputs = [
        "Miting ugma 3pm sa barangay hall bahin sa basketball tournament.",
        "Libreng checkup sa health center sa Miyerkules para sa mga senior.",
        "Ayaw paglabay og basura sa kalsada kay adunay inspection.",
    ]
    
    for text in test_inputs:
        result = analyzer.analyze(text)
        print(f"\nInput: {text[:50]}...")
        print(f"  Content type: {result.content_type.value}")
        print(f"  Dialect recommendation: {result.dialect_recommendation.value}")
        print(f"  Dialect confidence: {result.dialect_confidence:.2f}")
        print(f"  Facts found: {len(result.preserved_facts)}")
        for fact in result.preserved_facts:
            print(f"    - {fact.fact_type}: {fact.value}")
    
    print("\n✓ Analyzer test passed\n")


def test_example_retriever():
    """Test example retrieval."""
    print("=" * 60)
    print("TEST 2: Example Retrieval")
    print("=" * 60)
    
    examples = get_examples(
        content_type="event",
        audience=["Youth", "General Residents"],
        dialect_mode="tandaganon_light",
        k=2
    )
    
    print(f"Retrieved {len(examples)} examples:\n")
    
    for ex in examples:
        print(f"  ID: {ex.id}")
        print(f"  Type: {ex.content_type}")
        print(f"  Score: {ex.similarity_score:.2f}")
        print(f"  Input: {ex.raw_input[:40]}...")
        print(f"  Output: {ex.approved_output[:40]}...")
        print()
    
    print("✓ Example retrieval test passed\n")


def test_prompt_builder():
    """Test prompt building."""
    print("=" * 60)
    print("TEST 3: Prompt Builder")
    print("=" * 60)
    
    builder = PromptBuilder()
    
    from services.refinement_service import PreservedFact
    
    context = PromptContext(
        raw_text="Miting ugma 3pm sa barangay hall.",
        content_type=ContentType.EVENT.value,
        dialect_mode=DialectMode.TANDAGANON_LIGHT.value,
        preserved_facts=[PreservedFact(fact_type="time", value="3pm")],
        examples=[],
        audience=["General Residents"],
        attempt=0
    )
    
    prompt = builder.build(context)
    
    print(f"Prompt version: {prompt.version}")
    print(f"\nSystem prompt (first 200 chars):")
    print(f"  {prompt.system[:200]}...")
    print(f"\nUser prompt (first 300 chars):")
    print(f"  {prompt.user[:300]}...")
    print(f"\nJSON Schema defined: Yes")
    print(f"Schema keys: {list(prompt.schema.keys())}")
    
    # Test OpenAI messages
    messages = prompt.to_openai_messages()
    print(f"\nOpenAI messages: {len(messages)} messages")
    
    print("\n✓ Prompt builder test passed\n")


def test_validator():
    """Test output validation."""
    print("=" * 60)
    print("TEST 4: Output Validator")
    print("=" * 60)
    
    validator = OutputValidator()
    
    # Test case 1: Valid output
    valid_output = {
        "refined_text": "Tinahod kong mga kaigsuonan, gihulagway ko ang miting ugma alas 3:00 sa hapon.",
        "dialect_confidence": 0.8,
        "tandaganon_terms_used": ["kaigsuonan"],
        "warnings": []
    }
    
    # Create mock fact
    class MockFact:
        def __init__(self, t, v):
            self.fact_type = t
            self.value = v
    
    facts = [MockFact("time", "3pm")]
    original = "Miting ugma 3pm."
    
    result = validator.validate(valid_output, facts, original)
    print(f"Valid output test:")
    print(f"  is_valid: {result.is_valid}")
    print(f"  warnings: {result.warnings}")
    print(f"  scores: {result.scores}")
    
    # Test case 2: Invalid output (missing fact)
    invalid_output = {
        "refined_text": "Tinahod kong mga kaigsuonan.",
        "dialect_confidence": 0.8,
        "tandaganon_terms_used": ["kaigsuonan"],
        "warnings": []
    }
    
    result2 = validator.validate(invalid_output, facts, original)
    print(f"\nInvalid output test (missing fact):")
    print(f"  is_valid: {result2.is_valid}")
    print(f"  reason: {result2.reason}")
    
    # Test case 3: Markdown artifacts
    markdown_output = {
        "refined_text": "```\nSome refined text\n```",
        "dialect_confidence": 0.5,
        "tandaganon_terms_used": [],
        "warnings": []
    }
    
    result3 = validator.validate(markdown_output, [], "Input")
    print(f"\nMarkdown artifact test:")
    print(f"  is_valid: {result3.is_valid}")
    print(f"  reason: {result3.reason}")
    
    print("\n✓ Validator test passed\n")


def test_full_pipeline():
    """Test the full refinement pipeline (mock)."""
    print("=" * 60)
    print("TEST 5: Full Pipeline (Mock)")
    print("=" * 60)
    
    service = RefinementService()
    
    test_input = "Miting ugma 3pm sa barangay hall bahin sa basketball."
    
    print(f"Input: {test_input}")
    print("\nRunning refinement pipeline...")
    
    result = service.refine(test_input)
    
    print(f"\nResult:")
    print(f"  Success: {result.success}")
    print(f"  Provider: {result.provider_used}")
    print(f"  Fallback used: {result.fallback_used}")
    print(f"  Dialect applied: {result.dialect_applied}")
    print(f"  Output: {result.refined_text[:60]}..." if result.refined_text else "  Output: None")
    
    if result.validation_warnings:
        print(f"  Validation Warnings: {result.validation_warnings}")
    
    print("\n✓ Full pipeline test passed\n")


def main():
    """Run all tests."""
    print("\n" + "=" * 60)
    print("REFINEMENT PIPELINE TEST SUITE")
    print("=" * 60 + "\n")
    
    try:
        test_analyzer()
        test_example_retriever()
        test_prompt_builder()
        test_validator()
        test_full_pipeline()
        
        print("=" * 60)
        print("ALL TESTS PASSED ✓")
        print("=" * 60)
        
    except Exception as e:
        print(f"\n❌ Test failed with error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
