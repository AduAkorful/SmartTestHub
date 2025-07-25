from pyteal import *
import time

def measure_contract_performance(contract_path: str) -> dict:
    """Measure contract performance metrics"""
    metrics = {
        "start_time": time.time(),
        "teal_size": 0,
        "opcode_count": 0,
        "branches": 0
    }
    
    try:
        with open(contract_path, 'r') as f:
            content = f.read()
            
        # Compile to TEAL
        teal = compileTeal(
            approval_program(),
            mode=Mode.Application,
            version=6
        )
        
        metrics.update({
            "teal_size": len(teal.splitlines()),
            "opcode_count": len([l for l in teal.splitlines() if not l.startswith(('#', '//'))]),
            "compilation_time": time.time() - metrics["start_time"]
        })
        
    except Exception as e:
        metrics["error"] = str(e)
        
    return metrics
