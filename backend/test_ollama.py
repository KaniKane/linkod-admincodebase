"""Quick test script to check if Ollama is running and responsive."""

import sys
import httpx

def test_ollama():
    """Test if Ollama is running at localhost:11434."""
    base_url = "http://localhost:11434"
    
    print("Testing Ollama connection...")
    print(f"URL: {base_url}")
    print("-" * 40)
    
    try:
        # Check if Ollama is running
        response = httpx.get(f"{base_url}/api/tags", timeout=10)
        response.raise_for_status()
        data = response.json()
        
        print("✓ Ollama is RUNNING")
        print(f"\nAvailable models:")
        for model in data.get("models", []):
            print(f"  - {model.get('name', 'unknown')}")
        
        # Test a simple generation
        print("\nTesting generation with llama3.2:3b...")
        gen_response = httpx.post(
            f"{base_url}/api/generate",
            json={
                "model": "llama3.2:3b",
                "prompt": "Say 'test' and nothing else.",
                "stream": False,
            },
            timeout=30
        )
        gen_response.raise_for_status()
        gen_data = gen_response.json()
        
        if gen_data.get("response"):
            print(f"✓ Generation works!")
            print(f"  Response: {gen_data.get('response', '').strip()}")
        else:
            print("✗ Generation failed - empty response")
            
    except httpx.ConnectError as e:
        print(f"✗ Ollama is NOT running or not accessible")
        print(f"  Error: {e}")
        print("\nTo fix:")
        print("  1. Install Ollama: winget install Ollama.Ollama")
        print("  2. Pull model: ollama pull llama3.2:3b")
        print("  3. Start Ollama: ollama serve")
        sys.exit(1)
    except httpx.HTTPStatusError as e:
        print(f"✗ HTTP error: {e.response.status_code}")
        sys.exit(1)
    except Exception as e:
        print(f"✗ Unexpected error: {e}")
        sys.exit(1)
    
    print("\n" + "=" * 40)
    print("Ollama test PASSED")
    return 0

if __name__ == "__main__":
    sys.exit(test_ollama())
