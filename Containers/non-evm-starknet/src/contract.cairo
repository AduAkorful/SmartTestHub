%lang starknet

@contract_interface
namespace IContract:
    func foo() -> (res: felt):
    end

@external
func foo() -> (res: felt):
    return (res=42)
end
