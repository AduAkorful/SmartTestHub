import sys
import re
from pathlib import Path

def parse_functions(contract_path):
    src = Path(contract_path).read_text()
    # Find all external and view functions (this is a simple regex, can be improved)
    func_pattern = r'@(external|view)[^\n]*\s*\n\s*func\s+(\w+)\(([^\)]*)\)(?:\s*->\s*\((.*?)\))?:'
    matches = re.findall(func_pattern, src, re.MULTILINE)
    return matches

def gen_test_header():
    return '''import pytest
from starkware.starknet.testing.starknet import Starknet

@pytest.mark.asyncio
async def test_deploy():
    starknet = await Starknet.empty()
    # TODO: add contract deployment code here
    assert True
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
            else:
                arg_list.append('0') # General fallback
        else:
            arg_list.append('0')
    arg_str = ', '.join(arg_list)
    call_comment = f"# Call {func_name} with mock arguments"
    call_line = f"    # result = await contract.{func_name}.invoke({arg_str})"
    test_fn = f'''
@pytest.mark.asyncio
async def test_{func_name}():
    starknet = await Starknet.empty()
    # TODO: deploy contract and call {func_name}
    {call_comment}
    {call_line}
    assert True
'''
    return test_fn

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: generate_starknet_tests.py <input_contract.cairo> <output_test.py>")
        sys.exit(1)

    matches = parse_functions(sys.argv[1])
    output = gen_test_header()

    for func_type, func_name, args, returns in matches:
        output += gen_test_func(func_type, func_name, args, returns)

    Path(sys.argv[2]).write_text(output)
