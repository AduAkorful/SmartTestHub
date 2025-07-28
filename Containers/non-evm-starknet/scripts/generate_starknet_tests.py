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
    # Contract path should be relative to the test file, adjust as needed.
    return f'''import pytest
from starkware.starknet.testing.starknet import Starknet

@pytest.mark.asyncio
async def test_deploy_and_call_{contract_name}():
    starknet = await Starknet.empty()
    contract = await starknet.deploy(source="./src/contract.cairo")
    assert contract is not None
'''

def gen_test_func(func_type, func_name, args, returns):
    # Prepare mock arguments for function
    arg_list = []
    for arg in args.split(','):
        arg = arg.strip()
        if not arg:
            continue
        if ':' in arg:
            name, typ = arg.split(':', 1)
            if 'felt' in typ:
                arg_list.append('0')
            elif 'Array' in typ or 'array' in typ:
                arg_list.append('[]')
            else:
                arg_list.append('0') # General fallback
        else:
            arg_list.append('0')
    arg_str = ", ".join(arg_list)
    ret_comment = f"# TODO: check expected return values"
    # Try to call the function on the contract instance
    call_line = f"    result = await contract.{func_name}.invoke({arg_str})"
    test_fn = f'''
@pytest.mark.asyncio
async def test_{func_name}_call():
    starknet = await Starknet.empty()
    contract = await starknet.deploy(source="./src/contract.cairo")
    {call_line}
    {ret_comment}
    assert result is not None
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
