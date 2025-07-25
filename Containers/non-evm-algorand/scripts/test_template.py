import pytest
from pyteal import compileTeal, Mode
from algosdk import transaction
from algosdk.v2client import algod
import time
import importlib.util
import os

def import_contract(contract_name):
    """Dynamically import the contract module"""
    contract_path = f"/app/contracts/{contract_name}/src/contract.py"
    spec = importlib.util.spec_from_file_location("contract", contract_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

class TestAlgorandContract:
    @pytest.fixture(scope="class")
    def contract_module(self):
        """Load the contract module dynamically"""
        contract_name = os.environ.get('CONTRACT_NAME')
        if not contract_name:
            pytest.skip("No CONTRACT_NAME environment variable set")
        return import_contract(contract_name)

    @pytest.fixture(scope="class")
    def algod_client(self):
        """Setup Algorand client"""
        algod_token = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        algod_address = "http://localhost:4001"
        return algod.AlgodClient(algod_token, algod_address)

    def test_approval_program_compilation(self, contract_module):
        """Test if approval program compiles"""
        if hasattr(contract_module, 'approval_program'):
            teal = compileTeal(
                contract_module.approval_program(),
                mode=Mode.Application,
                version=6
            )
            assert teal and "#pragma version" in teal
        else:
            pytest.skip("No approval_program found in contract")

    def test_clear_state_program_compilation(self, contract_module):
        """Test if clear state program compiles"""
        if hasattr(contract_module, 'clear_state_program'):
            teal = compileTeal(
                contract_module.clear_state_program(),
                mode=Mode.Application,
                version=6
            )
            assert teal and "#pragma version" in teal
        else:
            pytest.skip("No clear_state_program found in contract")

    @pytest.mark.integration
    def test_app_creation(self, contract_module, algod_client):
        """Test application creation"""
        if not hasattr(contract_module, 'approval_program'):
            pytest.skip("No approval_program found in contract")

        creator_private_key, creator_address = account.generate_account()
        sp = algod_client.suggested_params()
        
        txn = transaction.ApplicationCreateTxn(
            sender=creator_address,
            sp=sp,
            on_complete=transaction.OnComplete.NoOpOC,
            approval_program=compileTeal(
                contract_module.approval_program(),
                mode=Mode.Application,
                version=6
            ),
            clear_program=compileTeal(
                contract_module.clear_state_program(),
                mode=Mode.Application,
                version=6
            ),
            global_schema=transaction.StateSchema(num_uints=1, num_byte_slices=1),
            local_schema=transaction.StateSchema(num_uints=0, num_byte_slices=0)
        )
        
        signed_txn = txn.sign(creator_private_key)
        try:
            tx_id = algod_client.send_transaction(signed_txn)
            transaction.wait_for_confirmation(algod_client, tx_id)
            assert True
        except Exception as e:
            pytest.fail(f"Application creation failed: {str(e)}")

    @pytest.mark.performance
    def test_opcode_count(self, contract_module):
        """Test TEAL opcode count"""
        if not hasattr(contract_module, 'approval_program'):
            pytest.skip("No approval_program found in contract")

        teal = compileTeal(
            contract_module.approval_program(),
            mode=Mode.Application,
            version=6
        )
        opcode_count = len([line for line in teal.split('\n') 
                           if line and not line.startswith(('#', '//'))])
        assert opcode_count < 1000, f"Too many opcodes: {opcode_count}"

    @pytest.mark.performance
    def test_state_access_performance(self, contract_module):
        """Test state access patterns"""
        if not hasattr(contract_module, 'approval_program'):
            pytest.skip("No approval_program found in contract")

        teal = compileTeal(
            contract_module.approval_program(),
            mode=Mode.Application,
            version=6
        )
        state_ops = ["app_global_get", "app_local_get", 
                     "app_global_put", "app_local_put"]
        access_count = sum(teal.count(op) for op in state_ops)
        assert access_count < 30, f"Too many state accesses: {access_count}"
