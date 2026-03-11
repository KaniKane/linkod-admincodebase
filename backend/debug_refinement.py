"""
Debug test to check why refined text equals original.
"""
import sys
sys.path.insert(0, 'd:/GitHub/linkod_admin/linkod-admincodebase/backend')

from services.refinement.refinement_service import refine_text_pipeline

# Test with a sample that should definitely be refined
result = refine_text_pipeline('miting sa martes alas 3', enable_logging=True, max_retries=0)

print()
print('=== RESULT ===')
print("Original: '%s'" % result['original_text'])
print("Refined:  '%s'" % result['refined_text'])
print("Same:     %s" % (result['original_text'].strip().lower() == result['refined_text'].strip().lower()))
print("Fallback: %s" % result.get('fallback_used', False))
print("Warnings: %s" % result.get('warnings', []))
print()
print("If refined equals original, check the logs above for [REFINE DEBUG] lines")
print("to see what the LLM actually returned.")
