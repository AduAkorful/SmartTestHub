"""
Utility modules for Algorand Smart Contract Testing
"""

from .test_runner import AlgorandTestRunner
from .test_generator import AlgorandTestGenerator

DEFAULT_ALGOD_ADDRESS = "http://localhost:4001"
DEFAULT_ALGOD_TOKEN = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
MAX_OPCODE_COUNT = 1000
MAX_STATE_OPS = 100

__all__ = [
    'AlgorandTestRunner',
    'AlgorandTestGenerator',
    'DEFAULT_ALGOD_ADDRESS',
    'DEFAULT_ALGOD_TOKEN',
    'MAX_OPCODE_COUNT',
    'MAX_STATE_OPS'
]
