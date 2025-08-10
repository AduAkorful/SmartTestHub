const fs = require('fs');
const path = require('path');
const axios = require('axios');
require('dotenv').config({ path: '/app/.env' });

const contractName = process.argv[2];
if (!contractName) {
  console.error("Contract name must be passed as argument to aggregate-all-logs.js");
  process.exit(1);
}

const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const GEMINI_MODEL = 'gemini-2.5-flash';
const GEMINI_URL = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

const outputFile = `/app/logs/reports/${contractName}-report.txt`;

function tryRead(file, fallback = '') {
  try {
    return fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : fallback;
  } catch (e) {
    return fallback;
  }
}

function tryList(dir, filter = () => true) {
  try {
    return fs.existsSync(dir) ? fs.readdirSync(dir).filter(filter) : [];
  } catch (e) {
    return [];
  }
}

function section(title, content) {
  return `\n\n## ${title}\n\n${content || '_No output found._'}`;
}

function aggregateDir(dir, filter = () => true) {
  return tryList(dir, f => f.startsWith(contractName) && filter(f))
    .map(f => `### File: ${f}\n` + tryRead(path.join(dir, f)))
    .join('\n\n');
}

let fullLog = '';
// Aggregate all tool outputs from the contract-specific results directory
const contractReportsDir = `/app/logs/reports/${contractName}`;

fullLog += section('PyTest Unit Tests', tryRead(`${contractReportsDir}/unittest.log`));
fullLog += section('PyTest Integration Tests', tryRead(`${contractReportsDir}/integration.log`));
fullLog += section('PyTest Performance Tests', tryRead(`${contractReportsDir}/performance.log`));
fullLog += section('Coverage Reports', tryRead(`${contractReportsDir}/coverage.xml`));
fullLog += section('Bandit Security Analysis', tryRead(`${contractReportsDir}/bandit.log`));
fullLog += section('MyPy Type Checking', tryRead(`${contractReportsDir}/mypy.log`));
fullLog += section('Flake8 Style Analysis', tryRead(`${contractReportsDir}/flake8.log`));
fullLog += section('Black Code Formatting', tryRead(`${contractReportsDir}/black.log`));
fullLog += section('TEAL Compilation Analysis', tryRead(`${contractReportsDir}/teal.log`));
fullLog += section('TEAL Compilation Errors', tryRead(`${contractReportsDir}/teal-error.log`));
// If SyntaxError flag exists, include it explicitly in the report
const statusFlag = tryRead(`${contractReportsDir}/.status`);
if (statusFlag && statusFlag.includes('SYNTAX_ERROR=1')) {
  fullLog += section('Detected SyntaxError', 'The contract source contained a SyntaxError; tests and coverage were effectively skipped to avoid misleading results.');
}
fullLog += section('Test Summary', tryRead(`${contractReportsDir}/summary.txt`));
fullLog += section('Other Logs', aggregateDir('/app/logs', f => f.endsWith('.log') && f.includes(contractName)));

fullLog += section('Tool Run Confirmation', `
The following tools were executed for ${contractName}:
- Testing: PyTest Unit Tests, Integration Tests, Performance Tests
- Coverage: pytest-cov for code coverage analysis
- Security Analysis: Bandit (security issues), MyPy (type checking), Flake8 (style issues)
- Code Quality: Black (formatting check)
- TEAL Analysis: PyTeal to TEAL compilation and metrics
- Performance: TEAL opcode counting and efficiency analysis

Tool Output Locations:
- All tool outputs are saved in: /app/logs/reports/${contractName}/
- Individual log files: unittest.log, integration.log, performance.log, bandit.log, mypy.log, flake8.log, black.log, teal.log

If any section above says "_No output found._", that tool either failed to run or produced no output.

Metadata:
- Generated: ${new Date().toISOString()}
- Container: Algorand PyTeal Analysis
- Contract: ${contractName}
`);

const prompt = `
You are an expert smart contract auditor specializing in Algorand/PyTeal contracts.
You are given the **raw logs and reports** from a full smart contract testing and analysis pipeline.

**IMPORTANT: Structure your response in exactly these 6 sections in this order:**

## 1. OVERVIEW
- Contract Information (file name, size, lines of code, contract type: Algorand PyTeal)
- Analysis Status (syntax check, TEAL compilation, testing status, security status, coverage status)
- Summary of all tools that ran and their overall results

## 2. TESTING
- Test execution results (passed/failed/skipped counts)
- PyTeal compilation test results
- TEAL generation and validation results
- Test coverage metrics and detailed test analysis
- Testing recommendations for Algorand-specific scenarios

## 3. SECURITY
- Security Summary with vulnerability counts (Critical: X, High: X, Medium: X, Low: X)
- Security Score assessment (e.g., "Good security with minor issues - Address the identified vulnerabilities")
- Detailed vulnerability findings with Algorand-specific security patterns
- Results from security tools (Bandit, Flake8, MyPy, custom Algorand analysis)
- Algorand security best practices and state management recommendations

## 4. CODE QUALITY
- Code quality score and overall assessment
- Python linting results (errors, warnings, style issues)
- PyTeal code metrics (complexity, maintainability, documentation quality)
- Algorand coding standards compliance and naming conventions
- Code improvement suggestions for PyTeal development

## 5. PERFORMANCE
- TEAL Analysis (compiled TEAL size, opcode count, execution cost estimates)
- Contract metrics (Python file size, complexity, TEAL efficiency)
- Performance recommendations and TEAL optimization opportunities
- Algorand transaction cost analysis and resource usage

## 6. AI SUMMARY
- Overall Assessment (Excellent/Good/Fair/Poor)
- Risk Level (Low/Medium/High/Critical)
- Deployment Readiness (Ready/Ready with improvements/Not ready)
- Key Findings (main observations and Algorand-specific issues)
- Priority Actions (most important next steps for PyTeal contracts)
- Recommendations (Algorand best practices and improvements)

**Analysis Guidelines:**
- Extract specific metrics from logs (file size, line counts, TEAL size, test numbers)
- Focus on Algorand-specific vulnerabilities and patterns
- Analyze PyTeal to TEAL compilation efficiency
- Identify state management and transaction handling issues
- Provide actionable recommendations for Algorand development
- Include specific line numbers and code references when available

Here are the complete logs and reports:
${fullLog}
`;

async function enhanceReport() {
  if (!GEMINI_API_KEY) {
    console.error("Error: GEMINI_API_KEY environment variable not set.");
    fs.writeFileSync(outputFile, "# Error: GEMINI_API_KEY not set. Cannot generate enhanced report.\n" + prompt);
    process.exit(1);
  }
  try {
    console.log("Sending request to Gemini 2.5 Flash endpoint...");
    const response = await axios.post(
      GEMINI_URL,
      {
        contents: [
          { parts: [{ text: prompt }] }
        ]
      },
      {
        headers: {
          "Content-Type": "application/json",
          "X-goog-api-key": GEMINI_API_KEY
        },
        timeout: 60000
      }
    );
    const aiSummary = 
      response.data?.candidates?.[0]?.content?.parts?.[0]?.text ||
      "Error: Malformed response from Gemini API.";
    fs.writeFileSync(outputFile, aiSummary);
    console.log(`AI-enhanced report written to ${outputFile}`);
  } catch (err) {
    console.error("AI enhancement failed, writing raw logs instead.", err?.message || err);
    fs.writeFileSync(outputFile, fullLog + "\n\n---\n\n# AI enhancement failed.\n");
  }
}

enhanceReport();
