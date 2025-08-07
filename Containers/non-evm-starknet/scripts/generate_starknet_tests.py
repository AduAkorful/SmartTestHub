import sys
import re
from pathlib import Path

def parse_functions(contract_path):
    src = Path(contract_path).read_text()
    # Find all external and view functions
    func_pattern = r'@(external|view)[^\n]*\s*\n\s*func\s+(\w+)\(([^\)]*)\)(?:\s*->\s*\((.*?)\))?:'
    matches = re.findall(func_pattern, src, re.MULTILINE)
    return matches

def gen_test_header(contract_name):
    # Generate basic tests that can run without complex StarkNet dependencies
    return f'''import pytest
import os
import sys
from pathlib import Path

# Basic tests for Cairo contract: {contract_name}

def test_contract_file_exists():
    """Test that the contract file exists and is readable"""
    contract_path = Path(__file__).parent.parent / "src" / "contract.cairo"
    assert contract_path.exists(), f"Contract file not found: {{contract_path}}"
    assert contract_path.is_file(), "Contract path is not a file"

def test_contract_not_empty():
    """Test that the contract file is not empty"""
    contract_path = Path(__file__).parent.parent / "src" / "contract.cairo"
    content = contract_path.read_text()
    assert len(content.strip()) > 0, "Contract file is empty"
    assert "func" in content or "contract" in content, "Contract file doesn't contain expected Cairo syntax"

def test_contract_syntax_basic():
    """Basic syntax check for Cairo contract"""
    contract_path = Path(__file__).parent.parent / "src" / "contract.cairo"
    content = contract_path.read_text()
    # Check for basic Cairo patterns
    assert not content.count("(") < content.count(")"), "Unmatched closing parentheses"
    assert not content.count("{{") < content.count("}}"), "Unmatched closing braces"
'''

def gen_test_func(func_type, func_name, args, returns):
    # Generate a simple test that checks if the function exists in the contract
    test_fn = f'''
def test_function_{func_name}_exists():
    """Test that function {func_name} is defined in the contract"""
    contract_path = Path(__file__).parent.parent / "src" / "contract.cairo"
    content = contract_path.read_text()
    assert "func {func_name}" in content, f"Function {func_name} not found in contract"
    
def test_function_{func_name}_signature():
    """Test that function {func_name} has proper Cairo syntax"""
    contract_path = Path(__file__).parent.parent / "src" / "contract.cairo"
    content = contract_path.read_text()
    # Look for the function definition
    import re
    pattern = r'@{func_type}\\s*\\n\\s*func\\s+{func_name}\\s*\\('
    matches = re.search(pattern, content)
    assert matches is not None, f"Function {func_name} with @{func_type} decorator not found"
'''
    return test_fn

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: generate_starknet_tests.py <input_contract.cairo> <output_test.py>")
        sys.exit(1)

    contract_path = sys.argv[1]
    output_path = sys.argv[2]
    contract_name = Path(contract_path).stem

    matches = parse_functions(contract_path)
    output = gen_test_header(contract_name)

    for func_type, func_name, args, returns in matches:
        output += gen_test_func(func_type, func_name, args, returns)

    Path(output_path).write_text(output)
