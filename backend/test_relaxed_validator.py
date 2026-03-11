"""
Test the relaxed validator with the user's problematic input.
"""
import sys
sys.path.insert(0, 'd:/GitHub/linkod_admin/linkod-admincodebase/backend')

from services.refinement.output_validator import validate_output, _check_expansion
from services.refinement.entity_extractor import extract_protected_facts

# The user's input that was failing
test_input = """I would like to inform all the youth who wants to join the basketball club to be on our baskeball court tommorow at 3pm. 
we will be having a meeting regarding our upcomming basketball tournament na . 
ipa higayon karong fiesta sa cagbaoto, gi awhag mong tanan nga mo attend karon"""

print("=== TESTING RELAXED VALIDATOR ===")
print()
print(f"Input: {test_input[:80]}...")
print()

# Test expansion check
expansion = _check_expansion("Gitawag ang tanan nga mo apil", test_input)
print(f"Expansion check (with meeting context):")
print(f"  Has expansion: {expansion['has_expansion']}")
print(f"  Details: {expansion['details']}")
print()

# Test fact extraction
facts = extract_protected_facts(test_input)
print(f"Extracted facts:")
print(f"  Times: {facts['times']}")
print(f"  Dates: {facts['dates']}")
print()

# Test full validation
refined_sample = "Gitawag ang tanan nga mo apil sa basketball club. Adunay miting ugma sa alas 3 sa hapon."
is_valid, errors, meta = validate_output(refined_sample, test_input, facts)
print(f"Validation result:")
print(f"  Is valid: {is_valid}")
print(f"  Errors: {errors}")
print()
print("With the relaxed validator, minor expansion errors should NOT cause fallback.")
