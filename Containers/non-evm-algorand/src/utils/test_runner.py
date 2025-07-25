import os
import sys
import pytest
import subprocess
import logging
from datetime import datetime
from typing import Dict, Any, List
from .test_generator import AlgorandTestGenerator

class AlgorandTestRunner:
    def __init__(self, contract_path: str, output_dir: str):
        self.contract_path = contract_path
        self.output_dir = output_dir
        self.contract_name = os.path.basename(contract_path).replace('.py', '')
        self.setup_logging()
        self.test_generator = AlgorandTestGenerator(contract_path)

    def setup_logging(self):
        """Configure logging with both file and console handlers"""
        self.logger = logging.getLogger('algorand_test')
        self.logger.setLevel(logging.INFO)
        formatter = logging.Formatter('[%(asctime)s] %(levelname)s: %(message)s')
        
        # Console handler
        ch = logging.StreamHandler()
        ch.setFormatter(formatter)
        self.logger.addHandler(ch)
        
        # File handler
        os.makedirs(self.output_dir, exist_ok=True)
        fh = logging.FileHandler(os.path.join(self.output_dir, 'test.log'))
        fh.setFormatter(formatter)
        self.logger.addHandler(fh)

    def run_tests(self) -> None:
        """Run comprehensive test suite"""
        self.logger.info(f"🔬 Running comprehensive test suite for {self.contract_name}...")
        
        try:
            # Generate test file
            test_dir = os.path.join(self.output_dir, self.contract_name, 'tests')
            os.makedirs(test_dir, exist_ok=True)
            test_file = os.path.join(test_dir, f'test_{self.contract_name}.py')
            with open(test_file, 'w') as f:
                f.write(self.test_generator.generate_test_suite())

            # Unit Tests
            self.logger.info("🧪 Running unit tests...")
            self._run_pytest(test_file, "unit", [
                "test_approval_program_compilation",
                "test_clear_state_program_compilation"
            ])
            self.logger.info("✅ Unit tests completed")
            
            # Integration Tests
            self.logger.info("🔄 Running integration tests...")
            self._run_pytest(test_file, "integration", ["test_app_creation"], "-m integration")
            self.logger.info("✅ Integration tests completed")
            
            # Performance Tests
            self.logger.info("⚡ Running performance tests...")
            self._run_pytest(test_file, "performance", [
                "test_opcode_count",
                "test_state_access_performance"
            ], "-m performance")
            self.logger.info("✅ Performance tests completed")
            
            # Security Analysis
            self.logger.info("🛡️ Running security analysis...")
            self._run_security_checks()
            self.logger.info("✅ Security analysis completed")
            
            # Static Analysis
            self.logger.info("🔍 Running static analysis...")
            self._run_static_analysis()
            self.logger.info("✅ Static analysis completed")
            
            # TEAL Analysis
            self.logger.info("📝 Analyzing TEAL output...")
            self._analyze_teal()
            self.logger.info("✅ TEAL analysis completed")
            
        except Exception as e:
            self.logger.error(f"❌ Error during test execution: {str(e)}")
            raise

    def _run_pytest(self, test_file: str, test_type: str, test_names: List[str], extra_args: str = "") -> None:
        """Run pytest with specific configuration"""
        report_dir = os.path.join(self.output_dir, 'reports')
        coverage_dir = os.path.join(self.output_dir, 'coverage')
        os.makedirs(report_dir, exist_ok=True)
        os.makedirs(coverage_dir, exist_ok=True)

        args = [
            test_file,
            "-v",
            f"--junitxml={os.path.join(report_dir, f'{self.contract_name}-{test_type}.xml')}",
            "--cov",
            f"--cov-report=html:{os.path.join(coverage_dir, f'{self.contract_name}-{test_type}-html')}",
            f"--cov-report=xml:{os.path.join(coverage_dir, f'{self.contract_name}-{test_type}.xml')}"
        ]
        
        if extra_args:
            args.extend(extra_args.split())
            
        pytest.main(args)

    def _run_security_checks(self) -> None:
        """Run security analysis tools"""
        security_dir = os.path.join(self.output_dir, 'security')
        os.makedirs(security_dir, exist_ok=True)
        
        # Run bandit
        subprocess.run([
            'bandit', '-r', self.contract_path,
            '-f', 'txt',
            '-o', os.path.join(security_dir, f'{self.contract_name}-bandit.log')
        ])

    def _run_static_analysis(self) -> None:
        """Run static analysis tools"""
        security_dir = os.path.join(self.output_dir, 'security')
        
        # Run mypy
        subprocess.run([
            'mypy', self.contract_path, '--strict',
            '--txt-report', os.path.join(security_dir, f'{self.contract_name}-mypy.log')
        ])
        
        # Run flake8
        subprocess.run([
            'flake8', self.contract_path,
            '--output-file', os.path.join(security_dir, f'{self.contract_name}-flake8.log')
        ])

    def _analyze_teal(self) -> None:
        """Generate and analyze TEAL code"""
        try:
            from pyteal import compileTeal, Mode
            import importlib.util
            
            spec = importlib.util.spec_from_file_location(
                self.contract_name, 
                self.contract_path
            )
            if spec and spec.loader:
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
                
                teal = compileTeal(
                    module.approval_program(),
                    mode=Mode.Application,
                    version=6
                )
                
                with open(os.path.join(self.output_dir, f'{self.contract_name}-teal.log'), 'w') as f:
                    f.write(teal)
                    
        except Exception as e:
            self.logger.error(f"❌ TEAL compilation failed: {str(e)}")
            raise
