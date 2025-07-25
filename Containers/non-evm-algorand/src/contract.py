"""
Algorand Smart Contract Template
Generated: 2025-07-24 11:32:52 UTC
Author: AduAkorful
"""

from pyteal import *

def approval_program():
    """
    Main approval program for the smart contract.
    This is the default template that handles basic approval logic.
    
    Returns:
        PyTeal expression that always approves
    """
    
    # Basic handle_creation
    handle_creation = Return(Int(1))
    
    # Basic handle_optin
    handle_optin = Return(Int(1))
    
    # Basic handle_closeout
    handle_closeout = Return(Int(1))
    
    # Basic handle_updateapp
    handle_updateapp = Return(Int(0))
    
    # Basic handle_deleteapp
    handle_deleteapp = Return(Int(0))
    
    # Main router for handling different transaction types
    program = Cond(
        [Txn.application_id() == Int(0), handle_creation],
        [Txn.on_completion() == OnComplete.OptIn, handle_optin],
        [Txn.on_completion() == OnComplete.CloseOut, handle_closeout],
        [Txn.on_completion() == OnComplete.UpdateApplication, handle_updateapp],
        [Txn.on_completion() == OnComplete.DeleteApplication, handle_deleteapp],
        [Txn.on_completion() == OnComplete.NoOp, Return(Int(1))]
    )
    
    return program

def clear_state_program():
    """
    Clear state program for the smart contract.
    This is called when an account clears its state for the application.
    
    Returns:
        PyTeal expression that always approves
    """
    return Return(Int(1))

# For testing and verification
if __name__ == "__main__":
    with open("approval.teal", "w") as f:
        compiled = compileTeal(approval_program(), mode=Mode.Application, version=6)
        f.write(compiled)
        
    with open("clear.teal", "w") as f:
        compiled = compileTeal(clear_state_program(), mode=Mode.Application, version=6)
        f.write(compiled)
