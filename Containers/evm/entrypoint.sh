#!/bin/bash
set -e

echo "🚀 Starting EVM container..."

# Set environment variables for better integration
export REPORT_GAS=true
export HARDHAT_NETWORK=hardhat
export SLITHER_CONFIG_FILE="./config/slither.config.json"

# Ensure required folders exist
mkdir -p /app/input
mkdir -p /app/logs
mkdir -p /app/contracts
mkdir -p /app/test
mkdir -p /app/logs/slither
mkdir -p /app/logs/coverage
mkdir -p /app/logs/gas
mkdir -p /app/logs/foundry
mkdir -p /app/logs/reports
mkdir -p /app/config
mkdir -p /app/scripts

LOG_FILE="/app/logs/evm-test.log"

# Clear old log (or comment this line if you prefer appending)
: > "$LOG_FILE"

# Function to log with timestamp
log_with_timestamp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Setup necessary dependencies for hardhat
setup_hardhat_environment() {
    log_with_timestamp "🔧 Setting up Hardhat environment..."
    
    # Create package.json if it doesn't exist
    if [ ! -f "/app/package.json" ]; then
        cat > "/app/package.json" <<EOF
{
  "name": "smart-test-hub",
  "version": "1.0.0",
  "description": "EVM testing environment",
  "scripts": {
    "test": "hardhat test",
    "gas": "REPORT_GAS=true hardhat test"
  },
  "author": "SmartTestHub",
  "license": "MIT"
}
EOF
    fi
    
    # Install minimal dependencies one by one to make it more robust
    cd /app
    
    # Try to install hardhat first (if not already installed)
    if ! npm list hardhat 2>/dev/null | grep -q "hardhat"; then
        log_with_timestamp "📦 Installing hardhat..."
        npm install --save-dev hardhat@^2.9.0 2>/dev/null || log_with_timestamp "⚠️ Failed to install hardhat"
    fi
    
    # Install mocha for test reporting
    if ! npm list mocha 2>/dev/null | grep -q "mocha"; then
        log_with_timestamp "📦 Installing mocha..."
        npm install --save-dev mocha@^9.1.3 2>/dev/null || log_with_timestamp "⚠️ Failed to install mocha"
    fi
    
    # Install chai for assertions
    if ! npm list chai 2>/dev/null | grep -q "chai"; then
        log_with_timestamp "📦 Installing chai..."
        npm install --save-dev chai@^4.3.4 2>/dev/null || log_with_timestamp "⚠️ Failed to install chai"
    fi
    
    # Install gas reporter
    if ! npm list hardhat-gas-reporter 2>/dev/null | grep -q "hardhat-gas-reporter"; then
        log_with_timestamp "📦 Installing hardhat-gas-reporter..."
        npm install --save-dev hardhat-gas-reporter@^1.0.8 2>/dev/null || log_with_timestamp "⚠️ Failed to install hardhat-gas-reporter"
    fi
    
    # Install coverage tool
    if ! npm list solidity-coverage 2>/dev/null | grep -q "solidity-coverage"; then
        log_with_timestamp "📦 Installing solidity-coverage..."
        npm install --save-dev solidity-coverage@^0.7.21 2>/dev/null || log_with_timestamp "⚠️ Failed to install solidity-coverage"
    fi
    
    # Install ethers directly if needed
    if ! npm list ethers 2>/dev/null | grep -q "ethers"; then
        log_with_timestamp "📦 Installing ethers..."
        npm install --save-dev ethers@^5.5.4 2>/dev/null || log_with_timestamp "⚠️ Failed to install ethers"
    fi
    
    # Create minimal hardhat config
    cat > "/app/hardhat.config.js" <<EOF
/**
 * SmartTestHub - Minimal Hardhat Configuration
 */

require('hardhat-gas-reporter');

// Optional plugins - only load if installed
try { require('solidity-coverage'); } catch (e) {}

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      { 
        version: "0.8.24",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        }
      },
      { version: "0.8.20" },
      { version: "0.8.18" },
      { version: "0.8.17" },
      { version: "0.6.12" },
    ],
  },
  networks: {
    hardhat: {
      chainId: 1337,
      allowUnlimitedContractSize: true,
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS === "true",
    currency: "USD",
    outputFile: "./logs/gas/gas-report.txt",
    noColors: true,
    showMethodSig: true,
    showTimeSpent: true,
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
};
EOF

    log_with_timestamp "✅ Hardhat environment setup complete"
}

# Create enhanced slither configuration
setup_slither_config() {
    log_with_timestamp "🔧 Setting up Slither configuration..."
    
    cat > "/app/config/slither.config.json" <<EOF
{
  "detectors_to_exclude": [],
  "exclude_informational": false,
  "exclude_low": false,
  "exclude_medium": false,
  "exclude_high": false,
  "solc_disable_warnings": false,
  "filter_paths": "node_modules",
  "solc": "solc"
}
EOF

    log_with_timestamp "✅ Slither configuration setup complete"
}

# Create a comprehensive contract analyzer
create_enhanced_analyzer() {
    log_with_timestamp "🔧 Creating enhanced contract analyzer..."
    
    cat > "/app/scripts/analyze-contract.js" <<EOF
/**
 * SmartTestHub - Enhanced Contract Analyzer
 * Provides detailed static analysis for Solidity contracts
 */
const fs = require('fs');
const path = require('path');

// ANSI color codes for console output
const colors = {
  reset: '\x1b[0m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  magenta: '\x1b[35m',
  cyan: '\x1b[36m',
  white: '\x1b[37m',
  bold: '\x1b[1m'
};

// Define the security checks
const securityChecks = [
    {
        name: 'tx.origin Authentication', 
        regex: /\btx\.origin\b/g,
        severity: 'HIGH',
        safe: false,
        description: 'Using tx.origin for authentication is vulnerable to phishing attacks. Use msg.sender instead.'
    },
    {
        name: 'Selfdestruct/Suicide', 
        regex: /\bselfdestruct\b|\bsuicide\b/g,
        severity: 'HIGH',
        safe: false,
        description: 'The use of selfdestruct/suicide allows a contract to be destroyed, which can be dangerous if accessible.'
    },
    {
        name: 'Delegatecall', 
        regex: /\bdelegatecall\b/g,
        severity: 'HIGH',
        safe: false,
        description: 'Delegatecall executes code in the context of the calling contract, which can be dangerous if misused.'
    },
    {
        name: 'Assembly Usage', 
        regex: /\bassembly\s*{/g,
        severity: 'MEDIUM',
        safe: false,
        description: 'Assembly blocks bypass Solidity safety features and may introduce bugs or vulnerabilities.'
    },
    {
        name: 'Unchecked External Call', 
        regex: /\.call\s*\{[^}]*\}\s*\([^)]*\)/g, 
        severity: 'MEDIUM',
        safe: false,
        description: 'External calls should check the return value to ensure they succeeded.'
    },
    {
        name: 'Timestamp Dependence', 
        regex: /block\.timestamp|now/g,
        severity: 'LOW',
        safe: false,
        description: 'Using block.timestamp (or now) can be manipulated by miners within certain bounds.'
    },
    {
        name: 'Reentrancy Guard',
        regex: /\bnonReentrant\b|\breentrant\b/g,
        severity: 'N/A',
        safe: true,
        description: 'Presence of reentrancy guards helps prevent reentrancy attacks.'
    },
    {
        name: 'SafeMath',
        regex: /\busing\s+SafeMath\b|\.add\(|\.sub\(|\.mul\(|\.div\(/g,
        severity: 'N/A',
        safe: true,
        description: 'SafeMath prevents integer overflow/underflow vulnerabilities (pre-Solidity 0.8.x).'
    },
    {
        name: 'Require Statements',
        regex: /\brequire\s*\(/g,
        severity: 'N/A',
        safe: true,
        description: 'Require statements validate conditions and revert on failure, improving contract robustness.'
    },
    {
        name: 'Revert Statements',
        regex: /\brevert\s*\(/g,
        severity: 'N/A',
        safe: true,
        description: 'Revert statements allow contracts to undo state changes when conditions are not met.'
    },
    {
        name: 'Error Handling',
        regex: /\btry\b|\bcatch\b/g,
        severity: 'N/A',
        safe: true,
        description: 'Try/catch blocks handle exceptions gracefully.'
    },
    {
        name: 'Input Validation', 
        regex: /\brequire\s*\([^)]*\>[^)]*\)|\brequire\s*\([^)]*\<[^)]*\)|\brequire\s*\([^)]*==[^)]*\)|\brequire\s*\([^)]*!=[^)]*\)/g,
        severity: 'N/A',
        safe: true,
        description: 'Input validation checks ensure variables are within acceptable ranges.'
    },
    {
        name: 'Potential Integer Overflow',
        regex: /\+\+|\+=|-=|\*=|\/=/g,
        severity: 'LOW',
        safe: false,
        description: 'Arithmetic operations that could potentially overflow (safe in Solidity 0.8.x+).'
    },
    {
        name: 'Constant State Variables',
        regex: /\bconstant\b/g,
        severity: 'N/A',
        safe: true,
        description: 'Using constant state variables improves gas efficiency.'
    },
    {
        name: 'Unbounded Loops',
        regex: /\bfor\s*\([^;]*;[^;]*;[^)]*\)/g,
        severity: 'MEDIUM',
        safe: false,
        description: 'Loops without bounds can cause the contract to run out of gas.'
    }
];

/**
 * Check Solidity version from pragmas
 * @param {string} content Contract content
 * @returns {string} Detected Solidity version
 */
function detectSolidityVersion(content) {
    const pragmaMatch = content.match(/pragma\s+solidity\s+([^;]+);/);
    return pragmaMatch ? pragmaMatch[1].trim() : 'Unknown';
}

/**
 * Detect contract inheritance
 * @param {string} content Contract content
 * @returns {string[]} List of parent contracts
 */
function detectInheritance(content) {
    const inheritanceMatch = content.match(/contract\s+[^\s{]+\s+is\s+([^{]+){/);
    if (!inheritanceMatch) return [];
    
    return inheritanceMatch[1].split(',').map(parent => parent.trim());
}

/**
 * Detect imports in the contract
 * @param {string} content Contract content
 * @returns {string[]} List of imported files
 */
function detectImports(content) {
    const importMatches = content.matchAll(/import\s+["']([^"']+)["'];/g);
    const imports = [];
    
    for (const match of importMatches) {
        imports.push(match[1]);
    }
    
    return imports;
}

/**
 * Detect custom modifiers
 * @param {string} content Contract content
 * @returns {string[]} List of custom modifiers
 */
function detectModifiers(content) {
    const modifierMatches = content.matchAll(/modifier\s+([^\s(]+)/g);
    const modifiers = [];
    
    for (const match of modifierMatches) {
        modifiers.push(match[1]);
    }
    
    return modifiers;
}

/**
 * Detect functions in the contract
 * @param {string} content Contract content
 * @returns {Object[]} Array of function objects with signature and visibility
 */
function detectFunctions(content) {
    const functionMatches = content.matchAll(/function\s+([^\s(]+)\s*\(([^)]*)\)(?:\s+([^\s{]+))?/g);
    const functions = [];
    
    for (const match of functionMatches) {
        functions.push({
            name: match[1],
            params: match[2].trim(),
            visibility: match[3] || 'public'
        });
    }
    
    return functions;
}

/**
 * Detect state variables in the contract
 * @param {string} content Contract content
 * @returns {Object[]} Array of state variable objects
 */
function detectStateVariables(content) {
    // This regex is simplified and may not catch all cases
    const stateVarMatches = content.matchAll(/(?:public|private|internal|constant)\s+([^\s;]+)\s+([^\s;=]+)/g);
    const stateVars = [];
    
    for (const match of stateVarMatches) {
        stateVars.push({
            type: match[1],
            name: match[2]
        });
    }
    
    return stateVars;
}

/**
 * Extract contract name from content
 * @param {string} content Contract content
 * @returns {string} Contract name
 */
function extractContractName(content) {
    const contractMatch = content.match(/contract\s+([^\s{]+)/);
    return contractMatch ? contractMatch[1] : 'UnknownContract';
}

/**
 * Main function to analyze a contract
 * @param {string} filePath Path to the contract file
 * @returns {Object} Analysis results
 */
function analyzeContract(filePath) {
    try {
        // Read the file
        if (!fs.existsSync(filePath)) {
            return { error: \`File not found: \${filePath}\` };
        }
        
        const content = fs.readFileSync(filePath, 'utf8');
        const stats = fs.statSync(filePath);
        
        // Extract basic info
        const contractName = extractContractName(content);
        const version = detectSolidityVersion(content);
        const parents = detectInheritance(content);
        const imports = detectImports(content);
        const modifiers = detectModifiers(content);
        const functions = detectFunctions(content);
        const stateVars = detectStateVariables(content);
        const lines = content.split('\\n');
        
        // Analyze security aspects
        const securityFindings = [];
        
        securityChecks.forEach(check => {
            const matches = content.match(check.regex);
            const count = matches ? matches.length : 0;
            
            let status;
            if (check.safe) {
                status = count > 0 ? '✅ Good' : '⚠️ Missing';
            } else {
                status = count > 0 ? '⚠️ Issue' : '✅ Good';
            }
            
            securityFindings.push({
                name: check.name,
                count: count,
                status: status,
                severity: check.severity,
                safe: check.safe,
                description: check.description
            });
        });
        
        // Identify issues with high severity first
        const securityIssues = securityFindings
            .filter(finding => !finding.safe && finding.count > 0)
            .sort((a, b) => {
                const severityWeight = { 'HIGH': 3, 'MEDIUM': 2, 'LOW': 1, 'N/A': 0 };
                return severityWeight[b.severity] - severityWeight[a.severity];
            });
            
        // Identify missing good practices
        const missingPractices = securityFindings
            .filter(finding => finding.safe && finding.count === 0);
        
        return {
            contractName,
            filePath,
            fileSize: stats.size,
            lineCount: lines.length,
            version,
            parents,
            imports,
            modifiers,
            functions,
            stateVars,
            securityFindings,
            securityIssues,
            missingPractices
        };
    } catch (error) {
        return { error: \`Error analyzing contract: \${error.message}\` };
    }
}

/**
 * Generate a markdown report from the analysis
 * @param {Object} analysis Analysis results
 * @returns {string} Markdown formatted report
 */
function generateMarkdownReport(analysis) {
    if (analysis.error) {
        return \`# Analysis Error\n\n\${analysis.error}\`;
    }
    
    // Build the markdown report
    let report = \`# Contract Analysis: \${analysis.contractName}\n\n\`;
    
    // Basic information
    report += \`## Basic Information\n\n\`;
    report += \`- **File**: \${path.basename(analysis.filePath)}\n\`;
    report += \`- **Contract Name**: \${analysis.contractName}\n\`;
    report += \`- **Solidity Version**: \${analysis.version}\n\`;
    report += \`- **File Size**: \${analysis.fileSize} bytes\n\`;
    report += \`- **Lines of Code**: \${analysis.lineCount}\n\n\`;
    
    // Inheritance
    if (analysis.parents.length > 0) {
        report += \`- **Inherits From**: \${analysis.parents.join(', ')}\n\n\`;
    }
    
    // Imports
    if (analysis.imports.length > 0) {
        report += \`## Imports\n\n\`;
        analysis.imports.forEach(imp => {
            report += \`- \${imp}\n\`;
        });
        report += \`\n\`;
    }
    
    // Functions
    if (analysis.functions.length > 0) {
        report += \`## Functions\n\n\`;
        analysis.functions.forEach(func => {
            report += \`- \`\`\`\${func.visibility}\`\`\` \`\`\`function \${func.name}(\${func.params})\`\`\`\n\`;
        });
        report += \`\n\`;
    }
    
    // Security issues - prioritize these at the top if any exist
    if (analysis.securityIssues.length > 0) {
        report += \`## ⚠️ Security Issues\n\n\`;
        analysis.securityIssues.forEach(issue => {
            report += \`### \${issue.severity === 'HIGH' ? '🚨 ' : issue.severity === 'MEDIUM' ? '⚠️ ' : '🔍 '}\${issue.name}\n\n\`;
            report += \`- **Severity**: \${issue.severity}\n\`;
            report += \`- **Occurrences**: \${issue.count}\n\`;
            report += \`- **Description**: \${issue.description}\n\n\`;
        });
    }
    
    // Missing best practices
    if (analysis.missingPractices.length > 0) {
        report += \`## 📝 Recommended Best Practices\n\n\`;
        analysis.missingPractices.forEach(practice => {
            report += \`### \${practice.name}\n\n\`;
            report += \`- **Description**: \${practice.description}\n\n\`;
        });
    }
    
    // Comprehensive security check results
    report += \`## Security Check Results\n\n\`;
    report += \`| Check | Status | Count | Severity |\n\`;
    report += \`|-------|--------|-------|----------|\n\`;
    analysis.securityFindings.forEach(finding => {
        report += \`| \${finding.name} | \${finding.status} | \${finding.count} | \${finding.severity || 'N/A'} |\n\`;
    });
    
    return report;
}

/**
 * Main execution function
 */
function main() {
    // Get the file path from command line arguments
    const args = process.argv.slice(2);
    const filePath = args[0] || './contracts/SimpleToken.sol';
    const outputPath = args[1] || './analysis-report.md';
    
    console.log(\`Analyzing contract: \${filePath}\`);
    const analysis = analyzeContract(filePath);
    
    if (analysis.error) {
        console.error(analysis.error);
        process.exit(1);
    }
    
    // Generate and save the report
    const report = generateMarkdownReport(analysis);
    fs.writeFileSync(outputPath, report);
    
    // Also output to console
    console.log(report);
    console.log(\`\nReport saved to \${outputPath}\`);
}

// Run the main function if this is executed as a script
if (require.main === module) {
    main();
}

// Export functions for potential reuse
module.exports = {
    analyzeContract,
    generateMarkdownReport
};
EOF

    chmod +x /app/scripts/analyze-contract.js
    log_with_timestamp "✅ Enhanced contract analyzer created"
}

# Create a detailed gas report formatter
create_gas_report_formatter() {
    log_with_timestamp "🔧 Creating gas report formatter..."
    
    cat > "/app/scripts/format-gas-report.js" <<EOF
/**
 * SmartTestHub - Gas Report Formatter
 * Enhances gas reports with more readable formatting and context
 */
const fs = require('fs');
const path = require('path');

function formatGasReport(inputFile, outputFile) {
    try {
        if (!fs.existsSync(inputFile)) {
            console.error(\`Input file not found: \${inputFile}\`);
            return false;
        }
        
        let content = fs.readFileSync(inputFile, 'utf8');
        
        // Parse the gas report and enhance it
        let enhancedReport = "# Detailed Gas Usage Report\\n\\n";
        
        // Add context about gas costs
        enhancedReport += "## Gas Cost Context\\n\\n";
        enhancedReport += "Gas is the computational cost unit in Ethereum. Optimizing gas usage is crucial for:\\n";
        enhancedReport += "- Reducing transaction costs for users\\n";
        enhancedReport += "- Ensuring contracts can fit within block gas limits\\n";
        enhancedReport += "- Avoiding out-of-gas errors in complex operations\\n\\n";
        
        // Add efficiency guidelines
        enhancedReport += "## Efficiency Guidelines\\n\\n";
        enhancedReport += "| Gas Cost | Classification | Description |\\n";
        enhancedReport += "|----------|---------------|-------------|\\n";
        enhancedReport += "| < 20,000 | Very Efficient | Excellent optimization |\\n";
        enhancedReport += "| 20,000 - 50,000 | Efficient | Good optimization |\\n";
        enhancedReport += "| 50,000 - 100,000 | Average | Could be improved |\\n";
        enhancedReport += "| 100,000 - 200,000 | Inefficient | Needs optimization |\\n";
        enhancedReport += "| > 200,000 | Very Inefficient | Critical optimization required |\\n\\n";
        
        // Add the original report data, parsed into markdown tables
        enhancedReport += "## Raw Gas Report\\n\\n";
        enhancedReport += "\\`\\`\\`\\n" + content + "\\n\\`\\`\\`\\n";
        
        // Write the enhanced report
        fs.writeFileSync(outputFile, enhancedReport);
        return true;
    } catch (error) {
        console.error(\`Error formatting gas report: \${error.message}\`);
        return false;
    }
}

// Run the formatter if executed directly
if (require.main === module) {
    const args = process.argv.slice(2);
    const inputFile = args[0] || './logs/gas/gas-report.txt';
    const outputFile = args[1] || './logs/reports/detailed-gas-report.md';
    
    const success = formatGasReport(inputFile, outputFile);
    if (success) {
        console.log(\`Enhanced gas report saved to \${outputFile}\`);
    }
}

module.exports = { formatGasReport };
EOF

    chmod +x /app/scripts/format-gas-report.js
    log_with_timestamp "✅ Gas report formatter created"
}

# Create a tool to extract detailed findings from slither output
create_slither_parser() {
    log_with_timestamp "🔧 Creating Slither findings parser..."
    
    cat > "/app/scripts/parse-slither.js" <<EOF
/**
 * SmartTestHub - Slither Output Parser
 * Extracts useful findings from Slither text output
 */
const fs = require('fs');
const path = require('path');

function parseSlitherOutput(inputFile, outputFile) {
    try {
        if (!fs.existsSync(inputFile)) {
            console.error(\`Input file not found: \${inputFile}\`);
            return false;
        }
        
        let content = fs.readFileSync(inputFile, 'utf8');
        let findings = [];
        
        // Extract findings using regex
        const findingRegex = /(\[.*?\])\s+(.*?):\s+(.*?)(?=\[|\$)/gs;
        let match;
        
        while ((match = findingRegex.exec(content)) !== null) {
            const severity = match[1].trim();
            const detector = match[2].trim();
            const description = match[3].trim();
            
            findings.push({
                severity,
                detector,
                description
            });
        }
        
        // Generate markdown report
        let markdownReport = "# Security Analysis Findings\\n\\n";
        
        if (findings.length === 0) {
            markdownReport += "✅ **No security issues detected**\\n\\n";
        } else {
            // Group findings by severity
            const highSeverity = findings.filter(f => f.severity.includes("High"));
            const mediumSeverity = findings.filter(f => f.severity.includes("Medium"));
            const lowSeverity = findings.filter(f => f.severity.includes("Low"));
            const infoSeverity = findings.filter(f => f.severity.includes("Informational"));
            const otherSeverity = findings.filter(f => !f.severity.includes("High") && 
                                                       !f.severity.includes("Medium") && 
                                                       !f.severity.includes("Low") && 
                                                       !f.severity.includes("Informational"));
            
            // Display a summary
            markdownReport += "## Summary\\n\\n";
            markdownReport += \`- 🚨 **High Severity Issues**: \${highSeverity.length}\\n\`;
            markdownReport += \`- ⚠️ **Medium Severity Issues**: \${mediumSeverity.length}\\n\`;
            markdownReport += \`- ℹ️ **Low Severity Issues**: \${lowSeverity.length}\\n\`;
            markdownReport += \`- 📝 **Informational Issues**: \${infoSeverity.length}\\n\\n\`;
            
            // Function to format a finding group
            const formatSeverityGroup = (group, emoji, title) => {
                if (group.length === 0) return "";
                
                let result = \`## \${emoji} \${title} Issues (\${group.length})\\n\\n\`;
                
                group.forEach((finding, idx) => {
                    result += \`### Issue #\${idx+1}: \${finding.detector}\\n\\n\`;
                    result += \`\${finding.description}\\n\\n\`;
                });
                
                return result;
            };
            
            // Add each severity group to the report
            markdownReport += formatSeverityGroup(highSeverity, "🚨", "High Severity");
            markdownReport += formatSeverityGroup(mediumSeverity, "⚠️", "Medium Severity");
            markdownReport += formatSeverityGroup(lowSeverity, "ℹ️", "Low Severity");
            markdownReport += formatSeverityGroup(infoSeverity, "📝", "Informational");
            
            if (otherSeverity.length > 0) {
                markdownReport += formatSeverityGroup(otherSeverity, "🔍", "Other");
            }
        }
        
        // Add standard recommendations for common issues
        markdownReport += "## Standard Recommendations\\n\\n";
        markdownReport += "### Best Practices\\n\\n";
        markdownReport += "- Always check return values of external calls\\n";
        markdownReport += "- Use SafeMath for arithmetic operations (if using Solidity < 0.8.0)\\n";
        markdownReport += "- Avoid using tx.origin for authorization\\n";
        markdownReport += "- Consider using OpenZeppelin contracts for standard functionality\\n";
        markdownReport += "- Implement reentrancy guards for external calls\\n";
        
        // Write the report
        fs.writeFileSync(outputFile, markdownReport);
        return true;
    } catch (error) {
        console.error(\`Error parsing Slither output: \${error.message}\`);
        return false;
    }
}

// Run the parser if executed directly
if (require.main === module) {
    const args = process.argv.slice(2);
    const inputFile = args[0] || './logs/slither/SimpleToken-report.txt';
    const outputFile = args[1] || './logs/reports/security-findings.md';
    
    const success = parseSlitherOutput(inputFile, outputFile);
    if (success) {
        console.log(\`Security findings saved to \${outputFile}\`);
    }
}

module.exports = { parseSlitherOutput };
EOF

    chmod +x /app/scripts/parse-slither.js
    log_with_timestamp "✅ Slither parser created"
}

# Create a sample Hardhat test file template
create_hardhat_test_template() {
    log_with_timestamp "🔧 Creating Hardhat test template..."
    
    cat > "/app/scripts/test-template.js" <<EOF
/**
 * SmartTestHub - Hardhat Test Template Generator
 * Creates a comprehensive test suite for a contract
 */
const fs = require('fs');
const path = require('path');

function generateTestTemplate(contractPath, outputPath) {
    try {
        if (!fs.existsSync(contractPath)) {
            console.error(\`Contract file not found: \${contractPath}\`);
            return false;
        }
        
        const contractName = path.basename(contractPath, '.sol');
        
        // Generate a comprehensive test file
        const testTemplate = `const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("${contractName} Contract Tests", function () {
  let contract;
  let owner;
  let addr1;
  let addr2;
  let addrs;

  // Deploy a new contract before each test
  beforeEach(async function () {
    // Get signers (accounts)
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
    
    // Deploy the contract
    const ContractFactory = await ethers.getContractFactory("${contractName}");
    contract = await ContractFactory.deploy();
    await contract.deployed();
  });

  // Test deployment
  describe("Deployment", function () {
    it("Should deploy successfully", async function () {
      expect(contract.address).to.be.properAddress;
    });
    
    it("Should set the right owner", async function () {
      // Note: This assumes the contract has an owner() function
      // If not, modify or remove this test
      try {
        const contractOwner = await contract.owner();
        expect(contractOwner).to.equal(owner.address);
      } catch (e) {
        // Skip this test if owner() doesn't exist
        this.skip();
      }
    });
  });
  
  // Test basic functionality
  describe("Basic Functionality", function () {
    // Add specific tests based on your contract functions
    it("Should support expected functions", async function () {
      // Add checks for your contract's specific functions
      // For example, for ERC20:
      // expect(typeof contract.transfer).to.equal('function');
      // expect(typeof contract.balanceOf).to.equal('function');
    });
  });
  
  // Test access control
  describe("Access Control", function () {
    it("Should restrict access to owner-only functions", async function () {
      // Example: Test that non-owners can't access restricted functions
      // Replace with actual owner-only functions in your contract
      /* Example:
      try {
        const nonOwnerCall = contract.connect(addr1).restrictedFunction();
        await expect(nonOwnerCall).to.be.revertedWith("Ownable: caller is not the owner");
      } catch (e) {
        // If this function doesn't exist, skip this test
        this.skip();
      }
      */
    });
  });
  
  // Test error conditions
  describe("Error Handling", function () {
    it("Should revert on invalid operations", async function () {
      // Add tests for expected revert conditions
      // Example: await expect(contract.someFunction(invalidArgs)).to.be.reverted;
    });
  });
  
  // Add more test categories based on your contract type
  // For example, for ERC20 tokens:
  /*
  describe("Token Transfers", function () {
    it("Should transfer tokens between accounts", async function () {
      // Transfer 50 tokens from owner to addr1
      await contract.transfer(addr1.address, 50);
      const addr1Balance = await contract.balanceOf(addr1.address);
      expect(addr1Balance).to.equal(50);
    });
    
    it("Should update balances after transfers", async function() {
      const initialOwnerBalance = await contract.balanceOf(owner.address);
      await contract.transfer(addr1.address, 100);
      await contract.transfer(addr2.address, 50);
      
      const finalOwnerBalance = await contract.balanceOf(owner.address);
      expect(finalOwnerBalance).to.equal(initialOwnerBalance.sub(150));
      
      const addr1Balance = await contract.balanceOf(addr1.address);
      expect(addr1Balance).to.equal(100);
      
      const addr2Balance = await contract.balanceOf(addr2.address);
      expect(addr2Balance).to.equal(50);
    });
  });
  */
});
`;

        // Write the test file
        fs.writeFileSync(outputPath, testTemplate);
        return true;
    } catch (error) {
        console.error(\`Error generating test template: \${error.message}\`);
        return false;
    }
}

// Run the generator if executed directly
if (require.main === module) {
    const args = process.argv.slice(2);
    const contractPath = args[0] || './contracts/SimpleToken.sol';
    const contractName = path.basename(contractPath, '.sol');
    const outputPath = args[1] || \`./test/\${contractName}.test.js\`;
    
    const success = generateTestTemplate(contractPath, outputPath);
    if (success) {
        console.log(\`Test template saved to \${outputPath}\`);
    }
}

module.exports = { generateTestTemplate };
EOF

    chmod +x /app/scripts/test-template.js
    log_with_timestamp "✅ Hardhat test template created"
}

# Create a comprehensive report generator
create_report_generator() {
    log_with_timestamp "🔧 Creating comprehensive report generator..."
    
    cat > "/app/scripts/generate-report.js" <<EOF
/**
 * SmartTestHub - Comprehensive Report Generator
 * Creates a unified report combining all analysis results
 */
const fs = require('fs');
const path = require('path');

function generateComprehensiveReport(contractName, outputPath) {
    try {
        const timestamp = new Date().toISOString().replace('T', ' ').substring(0, 19);
        let report = \`# SmartTestHub: Comprehensive Analysis for \${contractName}\n\n\`;
        report += \`**Generated at:** \${timestamp}\n\n\`;
        
        // Add toc
        report += \`## Table of Contents\n\n\`;
        report += \`1. [Contract Overview](#contract-overview)\n\`;
        report += \`2. [Security Analysis](#security-analysis)\n\`;
        report += \`3. [Test Results](#test-results)\n\`;
        report += \`4. [Gas Usage Analysis](#gas-usage-analysis)\n\`;
        report += \`5. [Size Analysis](#size-analysis)\n\`;
        report += \`6. [Recommendations](#recommendations)\n\n\`;
        
        // Contract Analysis Section
        report += \`## Contract Overview\n\n\`;
        const analysisPath = \`/app/logs/reports/\${contractName}-analysis.txt\`;
        
        if (fs.existsSync(analysisPath)) {
            const analysisContent = fs.readFileSync(analysisPath, 'utf8');
            // Extract interesting parts
            const contractInfoMatch = analysisContent.match(/Contract Analysis[\\s\\S]*?Lines of Code:[\\s\\S]*?\\n\\n/);
            if (contractInfoMatch) {
                report += contractInfoMatch[0] + '\n';
            }
        } else {
            report += \`*Contract analysis not available*\n\n\`;
        }
        
        // Security Analysis Section
        report += \`## Security Analysis\n\n\`;
        const securityPath = \`/app/logs/reports/security-findings.md\`;
        
        if (fs.existsSync(securityPath)) {
            const securityContent = fs.readFileSync(securityPath, 'utf8')
                .replace(/^# .*\\n\\n/, '') // Remove the heading
                .replace(/^## Standard Recommendations[\\s\\S]*$/, ''); // Remove standard recommendations
            report += securityContent + '\n';
        } else {
            const slitherPath = \`/app/logs/slither/\${contractName}-report.txt\`;
            if (fs.existsSync(slitherPath)) {
                report += \`Security analysis was performed but the results need manual review. See the raw output at: \`\`\`\${slitherPath}\`\`\`\n\n\`;
            } else {
                report += \`*Security analysis not available*\n\n\`;
            }
        }
        
        // Test Results Section
        report += \`## Test Results\n\n\`;
        
        // Check Foundry Test Results
        const foundryReportPath = '/app/logs/foundry/foundry-test-report.json';
        if (fs.existsSync(foundryReportPath)) {
            try {
                const foundryData = JSON.parse(fs.readFileSync(foundryReportPath, 'utf8'));
                report += \`### Foundry Tests\n\n\`;
                report += \`- **Status**: ${foundryData.success ? '✅ Passed' : '❌ Failed'}\n\`;
                
                if (foundryData.test_results) {
                    const testCount = Object.keys(foundryData.test_results).length;
                    const passedTests = Object.values(foundryData.test_results).filter(t => t.success).length;
                    report += \`- **Tests**: \${passedTests}/${testCount} passed\n\`;
                }
                report += '\n';
            } catch (e) {
                report += \`*Foundry test results could not be parsed*\n\n\`;
            }
        }
        
        // Check for Hardhat Test Results
        const hardhatResultPath = \`/app/logs/reports/\${contractName}-hardhat-tests.txt\`;
        if (fs.existsSync(hardhatResultPath)) {
            const hardhatResults = fs.readFileSync(hardhatResultPath, 'utf8');
            report += \`### Hardhat Tests\n\n\`;
            report += \`\`\`\n\${hardhatResults}\n\`\`\`\n\n\`;
        }
        
        // Gas Usage Section
        report += \`## Gas Usage Analysis\n\n\`;
        const gasReportPath = '/app/logs/gas/gas-report.txt';
        if (fs.existsSync(gasReportPath)) {
            const gasReportContent = fs.readFileSync(gasReportPath, 'utf8');
            report += \`### Gas Consumption\n\n\`;
            report += \`\`\`\n\${gasReportContent}\n\`\`\`\n\n\`;
            
            report += \`### Gas Optimization Tips\n\n\`;
            report += \`- Use \`\`\`view\`\`\` functions where possible\n\`;
            report += \`- Pack variables to use fewer storage slots\n\`;
            report += \`- Avoid unnecessary storage reads/writes inside loops\n\`;
            report += \`- Use events for storing data that doesn't need to be accessed on-chain\n\`;
        }
        
        // Size Analysis Section
        report += \`## Size Analysis\n\n\`;
        const sizePath = \`/app/logs/reports/\${contractName}-size.txt\`;
        if (fs.existsSync(sizePath)) {
            const sizeContent = fs.readFileSync(sizePath, 'utf8');
            report += \`\`\`\n\${sizeContent}\n\`\`\`\n\n\`;
            
            // Check if we need to warn about size
            if (sizeContent.includes('Exceeds limit')) {
                report += \`⚠️ **Warning**: Contract exceeds the EIP-170 size limit of 24KB and cannot be deployed to Ethereum Mainnet. Consider splitting functionality into multiple contracts.\n\n\`;
            }
        }
        
        // Recommendations Section
        report += \`## Recommendations\n\n\`;
        
        // Pull recommendations from security analysis
        const analysisFile = \`/app/logs/reports/\${contractName}-analysis.txt\`;
        if (fs.existsSync(analysisFile)) {
            const analysis = fs.readFileSync(analysisFile, 'utf8');
            
            // Extract security issues
            const securityIssues = [];
            const securitySection = analysis.match(/Simple Security Checks:[\\s\\S]*$/);
            if (securitySection) {
                const issues = securitySection[0].match(/- .*?: .*? - (⚠️ .*)/g);
                if (issues) {
                    issues.forEach(issue => {
                        securityIssues.push(issue.trim());
                    });
                }
            }
            
            if (securityIssues.length > 0) {
                report += \`### Security Recommendations\n\n\`;
                securityIssues.forEach(issue => {
                    report += \`- \${issue}\n\`;
                });
                report += '\n';
            }
        }
        
        // Standard best practices
        report += \`### General Best Practices\n\n\`;
        report += \`1. **Add Comprehensive Tests**: Aim for 100% code coverage\n\`;
        report += \`2. **Document Functions**: Use NatSpec comments for all public functions\n\`;
        report += \`3. **Perform Code Review**: Have at least one other developer review the code\n\`;
        report += \`4. **Consider Formal Verification**: For high-value contracts\n\`;
        report += \`5. **Use Established Patterns**: Import from established libraries like OpenZeppelin\n\`;
        
        // Write the report
        fs.writeFileSync(outputPath, report);
        return true;
    } catch (error) {
        console.error(\`Error generating comprehensive report: \${error.message}\`);
        return false;
    }
}

// Run the generator if executed directly
if (require.main === module) {
    const args = process.argv.slice(2);
    const contractName = args[0] || 'SimpleToken';
    const outputPath = args[1] || \`/app/logs/reports/\${contractName}-comprehensive-report.md\`;
    
    const success = generateComprehensiveReport(contractName, outputPath);
    if (success) {
        console.log(\`Comprehensive report saved to \${outputPath}\`);
    }
}

module.exports = { generateComprehensiveReport };
EOF

    chmod +x /app/scripts/generate-report.js
    log_with_timestamp "✅ Comprehensive report generator created"
}

# Setup the environment
setup_hardhat_environment
setup_slither_config
create_enhanced_analyzer
create_gas_report_formatter
create_slither_parser
create_hardhat_test_template
create_report_generator

# Initialize git if not already done (required for some tools)
if [ ! -d ".git" ]; then
    git init . 2>/dev/null || true
    git config user.name "SmartTestHub" 2>/dev/null || true
    git config user.email "test@smarttesthub.com" 2>/dev/null || true
fi

# Watch the input folder where backend will drop .sol files
log_with_timestamp "📡 Watching /app/input for incoming Solidity files..."

# Use a marker file to prevent duplicate processing
MARKER_DIR="/app/.processed"
mkdir -p "$MARKER_DIR"

inotifywait -m -e close_write,moved_to,create /app/input |
while read -r directory events filename; do
  if [[ "$filename" == *.sol ]]; then
    # Check if file was already processed (prevent duplicates)
    MARKER_FILE="$MARKER_DIR/$filename.processed"
    if [ -f "$MARKER_FILE" ]; then
        LAST_PROCESSED=$(cat "$MARKER_FILE")
        CURRENT_TIME=$(date +%s)
        # Only process if last processed more than 30 seconds ago
        if (( $CURRENT_TIME - $LAST_PROCESSED < 30 )); then
            log_with_timestamp "⏭️ Skipping duplicate processing of $filename (processed ${LAST_PROCESSED}s ago)"
            continue
        fi
    fi
    
    {
      # Mark file as processed with timestamp
      date +%s > "$MARKER_FILE"
      
      log_with_timestamp "🆕 Detected Solidity contract: $filename"

      # Move file to /app/contracts (overwrite if same name exists)
      mkdir -p /app/contracts
      cp "/app/input/$filename" "/app/contracts/$filename"
      log_with_timestamp "📁 Copied $filename to contracts directory"

      # Extract contract name for better reporting
      contract_name=$(basename "$filename" .sol)
      contract_path="/app/contracts/$filename"
      
      # Step 1: Compile the contract
      log_with_timestamp "🔨 Compiling contract..."
      
      # Try direct solc compilation first (more reliable)
      mkdir -p /app/artifacts
      if solc --bin --abi --optimize --overwrite -o /app/artifacts "$contract_path" 2>/dev/null; then
        log_with_timestamp "✅ Direct Solidity compilation successful"
      else
        log_with_timestamp "⚠️ Direct compilation had issues, trying Hardhat..."
        
        # Try Hardhat compilation as backup
        if npx hardhat compile 2>&1 | tee /app/logs/reports/compilation.txt; then
          log_with_timestamp "✅ Hardhat compilation successful"
        else
          log_with_timestamp "❌ Compilation failed - check logs/reports/compilation.txt"
          # Continue anyway to provide partial analysis
        fi
      fi
      
      # Step 2: Generate a comprehensive test file if none exists
      if [ ! -f "/app/test/${contract_name}.test.js" ]; then
        log_with_timestamp "📝 Generating a comprehensive test file..."
        if node /app/scripts/test-template.js "$contract_path" "/app/test/${contract_name}.test.js"; then
          log_with_timestamp "✅ Test file generated successfully"
        else
          log_with_timestamp "⚠️ Failed to generate test file, creating a simple one"
          
          # Create a simple test file as fallback
          cat > "/app/test/${contract_name}.test.js" <<EOF
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("${contract_name}", function () {
  let contract;
  
  beforeEach(async function () {
    try {
      const Contract = await ethers.getContractFactory("${contract_name}");
      contract = await Contract.deploy();
      await contract.deployed();
    } catch (e) {
      console.log("Deployment error, some tests will be skipped:", e.message);
    }
  });

  it("Should deploy successfully", async function () {
    if (!contract) this.skip();
    expect(contract.address).to.be.properAddress;
  });
});
EOF
          log_with_timestamp "✅ Simple test file created"
        fi
      fi
      
      # Step 3: Run Hardhat tests if possible
      log_with_timestamp "🧪 Running Hardhat tests..."
      if npx hardhat test --network hardhat 2>&1 | tee "/app/logs/reports/${contract_name}-hardhat-tests.txt"; then
        log_with_timestamp "✅ Hardhat tests completed"
      else
        log_with_timestamp "⚠️ Hardhat tests had issues - check the logs"
      fi
      
      # Step 4: Run Foundry tests if any .t.sol files exist
      if compgen -G './test/*.t.sol' > /dev/null 2>&1; then
        log_with_timestamp "🧪 Running Foundry tests with gas reporting..."
        if forge test --gas-report --json > ./logs/foundry/foundry-test-report.json 2>&1 | tee -a "$LOG_FILE"; then
          log_with_timestamp "✅ Foundry tests passed with gas report"
        else
          log_with_timestamp "❌ Foundry tests failed - check logs/foundry/foundry-test-report.json"
        fi
        
        # Generate forge coverage
        log_with_timestamp "📊 Generating Foundry coverage report..."
        if forge coverage --report lcov --report-file ./logs/coverage/foundry-lcov.info 2>&1 | tee -a "$LOG_FILE"; then
          log_with_timestamp "✅ Foundry coverage report generated"
        else
          log_with_timestamp "⚠️ Foundry coverage generation failed"
        fi
      else
        log_with_timestamp "ℹ️ No Foundry test files found, skipping forge test"
      fi

      # Step 5: Run detailed contract analysis
      log_with_timestamp "🔍 Performing enhanced contract analysis..."
      if node /app/scripts/analyze-contract.js "$contract_path" "/app/logs/reports/${contract_name}-analysis.txt"; then
        log_with_timestamp "✅ Enhanced contract analysis completed"
      else
        log_with_timestamp "⚠️ Contract analysis failed"
      fi
      
      # Step 6: Run gas reporter
      log_with_timestamp "⛽ Generating detailed gas report..."
      if REPORT_GAS=true npx hardhat test 2>&1 | tee ./logs/gas/gas-report.txt; then
        log_with_timestamp "✅ Gas report generated"
        
        # Format the gas report
        if node /app/scripts/format-gas-report.js "./logs/gas/gas-report.txt" "./logs/reports/${contract_name}-gas-report.md"; then
          log_with_timestamp "✅ Enhanced gas report created"
        fi
      else
        log_with_timestamp "⚠️ Gas reporting failed"
      fi
      
      # Step 7: Run Slither security analysis
      log_with_timestamp "🛡️ Running Slither security analysis..."
      if slither "$contract_path" --solc solc > "./logs/slither/${contract_name}-report.txt" 2>&1; then
        log_with_timestamp "✅ Slither analysis completed"
      else
        log_with_timestamp "⚠️ Slither found security issues - check the report"
      fi
      
      # Parse Slither output
      if [ -f "./logs/slither/${contract_name}-report.txt" ]; then
        if node /app/scripts/parse-slither.js "./logs/slither/${contract_name}-report.txt" "./logs/reports/security-findings.md"; then
          log_with_timestamp "✅ Security findings extracted"
        fi
      fi
      
      # Step 8: Analyze contract size
      log_with_timestamp "📏 Analyzing contract size..."
      filesize=$(stat -c%s "$contract_path")
      echo "Contract: $contract_name" > "./logs/reports/${contract_name}-size.txt"
      echo "Source size: $filesize bytes" >> "./logs/reports/${contract_name}-size.txt"
      
      # If binary was generated, get its size too
      if [ -f "/app/artifacts/${contract_name}.bin" ]; then
        binsize=$(stat -c%s "/app/artifacts/${contract_name}.bin")
        hexsize=$((binsize / 2))
        echo "Compiled size: $hexsize bytes" >> "./logs/reports/${contract_name}-size.txt"
        echo "EIP-170 limit: 24576 bytes" >> "./logs/reports/${contract_name}-size.txt"
        if [ "$hexsize" -gt 24576 ]; then
          echo "Status: Exceeds limit ❌" >> "./logs/reports/${contract_name}-size.txt"
        else
          echo "Status: Within limit ✅" >> "./logs/reports/${contract_name}-size.txt"
        fi
      fi
      log_with_timestamp "✅ Contract size analysis completed"

      # Step 9: Generate comprehensive report
      log_with_timestamp "📋 Generating comprehensive report..."
      if node /app/scripts/generate-report.js "$contract_name" "./logs/reports/${contract_name}-comprehensive-report.md"; then
        log_with_timestamp "✅ Comprehensive report generated"
      else
        log_with_timestamp "⚠️ Report generation had issues"
      fi

      log_with_timestamp "🏁 All EVM analysis complete for $filename"
      log_with_timestamp "📊 Full report available at: logs/reports/${contract_name}-comprehensive-report.md"
      log_with_timestamp "==========================================\n"
      
    } 2>&1
  fi
done
