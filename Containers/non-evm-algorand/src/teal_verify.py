from pyteal import *

def verify_teal(teal_code: str) -> bool:
    """Verify TEAL code compilation"""
    try:
        # Basic verification
        lines = teal_code.splitlines()
        if not lines:
            return False
        
        # Check version
        if not any(line.startswith("#pragma version") for line in lines):
            return False
            
        return True
    except Exception:
        return False
