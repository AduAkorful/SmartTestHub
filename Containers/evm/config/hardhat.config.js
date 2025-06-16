require("@nomicfoundation/hardhat-toolbox");
require("hardhat-gas-reporter");
require("hardhat-contract-sizer");
require("hardhat-storage-layout");
require("@openzeppelin/hardhat-upgrades");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.18",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    hardhat: {} // Required for coverage
  },
  gasReporter: {
    enabled: true,
    currency: 'USD',
    outputFile: 'logs/gas/gas-report.txt',
    noColors: true
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
    strict: true,
    outputFile: 'logs/reports/contract-sizes.txt'
  }
};
