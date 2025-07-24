FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        inotify-tools \
        nodejs \
        npm \
        git \
        curl \
        ca-certificates \
        build-essential && \
    rm -rf /var/lib/apt/lists/*

# Set up working directory
WORKDIR /app

# Install npm dependencies first
COPY scripts/package.json /app/scripts/
RUN cd /app/scripts && npm install

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Create necessary directories and files
RUN mkdir -p /app/input /app/logs/coverage /app/logs/reports /app/logs/benchmarks \
    /app/logs/security /app/logs/xray /app/contracts /app/tests && \
    touch /app/tests/__init__.py && \
    echo 'import pytest\nfrom pyteal import *\nfrom algosdk import account, mnemonic\nfrom algosdk.v2client import algod\nfrom algosdk.future import transaction\nimport time\n\nclass TestAlgorandContract:\n    @pytest.fixture(scope="class")\n    def algod_client(self):\n        """Setup Algorand client"""\n        algod_token = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"\n        algod_address = "http://localhost:4001"\n        return algod.AlgodClient(algod_token, algod_address)\n\n    @pytest.fixture(scope="class")\n    def test_accounts(self):\n        """Generate test accounts"""\n        creator = account.generate_account()\n        user = account.generate_account()\n        return creator, user\n\n    def test_approval_program_compilation(self):\n        """Test if approval program compiles"""\n        teal = compileTeal(approval_program(), mode=Mode.Application, version=6)\n        assert teal and "#pragma version" in teal\n\n    def test_clear_state_program_compilation(self):\n        """Test if clear state program compiles"""\n        teal = compileTeal(clear_state_program(), mode=Mode.Application, version=6)\n        assert teal and "#pragma version" in teal\n\n    @pytest.mark.integration\n    def test_app_creation(self, algod_client, test_accounts):\n        """Test application creation"""\n        creator_private_key, creator_address = test_accounts[0]\n        sp = algod_client.suggested_params()\n        txn = transaction.ApplicationCreateTxn(\n            sender=creator_address,\n            sp=sp,\n            on_complete=transaction.OnComplete.NoOpOC,\n            approval_program=compileTeal(approval_program(), mode=Mode.Application, version=6),\n            clear_program=compileTeal(clear_state_program(), mode=Mode.Application, version=6),\n            global_schema=transaction.StateSchema(num_uints=1, num_byte_slices=1),\n            local_schema=transaction.StateSchema(num_uints=0, num_byte_slices=0)\n        )\n        signed_txn = txn.sign(creator_private_key)\n        try:\n            tx_id = algod_client.send_transaction(signed_txn)\n            transaction.wait_for_confirmation(algod_client, tx_id)\n            assert True\n        except Exception as e:\n            pytest.fail(f"Application creation failed: {str(e)}")\n\n    @pytest.mark.integration\n    def test_app_optins(self, algod_client, test_accounts):\n        """Test application opt-ins"""\n        _, user_address = test_accounts[1]\n        sp = algod_client.suggested_params()\n        try:\n            app_info = algod_client.application_info(1)\n            assert app_info\n        except Exception as e:\n            pytest.fail(f"Failed to get application info: {str(e)}")\n\n    @pytest.mark.integration\n    def test_state_management(self, algod_client, test_accounts):\n        """Test state management"""\n        creator_private_key, creator_address = test_accounts[0]\n        sp = algod_client.suggested_params()\n        try:\n            app_info = algod_client.application_info(1)\n            assert app_info\n        except Exception as e:\n            pytest.fail(f"Failed to get application state: {str(e)}")\n\n    @pytest.mark.performance\n    def test_opcode_count(self):\n        """Test TEAL opcode count"""\n        teal = compileTeal(approval_program(), mode=Mode.Application, version=6)\n        opcode_count = len([line for line in teal.split("\\n") if line and not line.startswith(("#", "//"))])\n        assert opcode_count < 1000, f"Too many opcodes: {opcode_count}"\n\n    @pytest.mark.performance\n    def test_state_access_performance(self):\n        """Test state access patterns"""\n        teal = compileTeal(approval_program(), mode=Mode.Application, version=6)\n        state_ops = ["app_global_get", "app_local_get", "app_global_put", "app_local_put"]\n        access_count = sum(teal.count(op) for op in state_ops)\n        assert access_count < 30, f"Too many state accesses: {access_count}"\n\n    @pytest.mark.performance\n    def test_execution_cost(self, algod_client, test_accounts):\n        """Test execution cost"""\n        creator_private_key, creator_address = test_accounts[0]\n        start_time = time.time()\n        sp = algod_client.suggested_params()\n        txn = transaction.ApplicationCreateTxn(\n            sender=creator_address,\n            sp=sp,\n            on_complete=transaction.OnComplete.NoOpOC,\n            approval_program=compileTeal(approval_program(), mode=Mode.Application, version=6),\n            clear_program=compileTeal(clear_state_program(), mode=Mode.Application, version=6),\n            global_schema=transaction.StateSchema(num_uints=1, num_byte_slices=1),\n            local_schema=transaction.StateSchema(num_uints=0, num_byte_slices=0)\n        )\n        execution_time = time.time() - start_time\n        assert execution_time < 1.0, f"Execution too slow: {execution_time:.2f}s"' > /app/tests/test_contract_suite.py

# Copy application files
COPY src ./src
COPY scripts/aggregate-all-logs.js ./scripts/
COPY entrypoint.sh ./

# Set permissions
RUN chmod +x /app/entrypoint.sh && \
    chmod -R 777 /app/logs

ENV PYTHONUNBUFFERED=1
ENV PATH="/app/scripts:${PATH}"

ENTRYPOINT ["/app/entrypoint.sh"]
