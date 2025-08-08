const fs = require('fs');
const path = require('path');
const axios = require('axios');
require('dotenv').config({ path: '/app/.env' });

const contractName = process.argv[2]; // first arg is contract name
if (!contractName) {
  console.error("Contract name must be passed as argument to aggregate-all-logs.js");
  process.exit(1);
}

const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const GEMINI_MODEL = 'gemini-2.5-flash';
const GEMINI_URL = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

// Output file
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

// Only aggregate logs for this contract - STRICT filtering
function aggregateDir(dir, filter = () => true) {
  return tryList(dir, f => {
    // STRICT: Only files that start with EXACT contract name and are current
    const isExactMatch = f.startsWith(contractName + '-') || f.startsWith(contractName + '.');
    const isCurrentFile = f.includes(contractName);
    return isExactMatch && isCurrentFile && filter(f);
  })
    .map(f => `### File: ${f}\n` + tryRead(path.join(dir, f)))
    .join('\n\n');
}

let fullLog = '';
// Docker process logs removed to reduce length - only tool-specific outputs included
// Aggregate logs with better organization
fullLog += section('Foundry Test Reports', aggregateDir('/app/logs/foundry', f => f.startsWith(contractName) && (f.endsWith('.json') || f.endsWith('.txt'))));
fullLog += section('Foundry Coverage Reports', aggregateDir('/app/logs/coverage', f => f.startsWith(contractName) && (f.endsWith('.info') || f.endsWith('.json') || f.endsWith('.txt'))));
fullLog += section('Slither Security Reports', aggregateDir('/app/logs/slither', f => f.startsWith(contractName) && (f.endsWith('.txt') || f.endsWith('.json'))));
fullLog += section('Mythril Security Reports', aggregateDir('/app/logs/slither', f => f.startsWith(contractName) && f.includes('mythril')));
fullLog += section('AI Summaries and Reports', aggregateDir('/app/logs/reports', f => f.startsWith(contractName) && (f.endsWith('.md') || f.endsWith('.txt'))));
fullLog += section('Other Analysis Logs', aggregateDir('/app/logs', f => f.startsWith(contractName) && f.endsWith('.log') && !f.includes('evm-test.log')));

fullLog += section('Tool Run Confirmation', `
The following tools' logs were aggregated for ${contractName}:
- Testing: Foundry (test results, gas reports), Coverage analysis
- Security: Slither (static analysis), Mythril (symbolic execution) 
- Analysis: Contract size analysis, AI-powered code review
- Reports: All generated summaries and detailed findings
- Other: Container-specific analysis logs
If any section above says "_No output found._", that tool was not available or did not run successfully.

Analysis Quality Notes:
- JSON outputs are parsed for structured data extraction
- Text outputs provide human-readable details  
- Multiple security tools ensure comprehensive coverage
- Gas reporting provides performance insights
`);

const prompt = `
You are an expert smart contract auditor specializing in EVM/Solidity contracts.
You are given the **raw logs and reports** from a full smart contract testing and analysis pipeline.

**IMPORTANT: Structure your response in exactly these 6 sections in this order:**

## 1. OVERVIEW
- Contract Information (file name, size, lines of code, contract type)
- Analysis Status (compilation success/failure, testing status, security status, coverage status)
- Summary of all tools that ran and their overall results

## 2. TESTING
- Test execution results (passed/failed/skipped counts)
- Test coverage metrics (overall %, statement %, branch %, function %)
- Detailed test results and any test failures
- Testing recommendations and missing test scenarios

## 3. SECURITY
- Security Summary with vulnerability counts (Critical: X, High: X, Medium: X, Low: X)
- Security Score assessment (e.g., "Good security with minor issues - Address the identified vulnerabilities")
- Detailed vulnerability findings with severity, description, and fix recommendations
- Results from security tools (Slither, Mythril, custom analysis)
- Security best practices recommendations

## 4. CODE QUALITY
- Code quality score and overall assessment
- Linting results (errors, warnings, style issues)
- Code metrics (complexity, maintainability, documentation quality)
- Naming conventions and coding standards compliance
- Code improvement suggestions

## 5. PERFORMANCE
- Gas analysis (deployment cost, average function gas usage, optimization suggestions)
- Contract metrics (size, complexity, dependencies)
- Performance recommendations and optimization opportunities
- Efficiency analysis and resource usage

## 6. AI SUMMARY
- Overall Assessment (Excellent/Good/Fair/Poor)
- Risk Level (Low/Medium/High/Critical)
- Deployment Readiness (Ready/Ready with improvements/Not ready)
- Key Findings (main observations and critical issues)
- Priority Actions (most important next steps)
- Recommendations (best practices and improvements)

**Analysis Guidelines:**
- Extract specific metrics from logs (file size, line counts, test numbers, gas usage)
- Identify and categorize all issues by severity
- Provide actionable recommendations for each finding
- Use clear, developer-friendly language
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
