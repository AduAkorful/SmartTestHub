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

// Only aggregate logs for this contract
function aggregateDir(dir, filter = () => true) {
  return tryList(dir, f => f.startsWith(contractName) && filter(f))
    .map(f => `### File: ${f}\n` + tryRead(path.join(dir, f)))
    .join('\n\n');
}

let fullLog = '';
// Docker process logs removed to reduce length - only tool-specific outputs included
fullLog += section('Foundry Test Reports', aggregateDir('/app/logs/foundry', f => f.endsWith('.json') || f.endsWith('.txt')));
fullLog += section('Foundry Coverage Reports', aggregateDir('/app/logs/coverage', f => f.endsWith('.info') || f.endsWith('.json') || f.endsWith('.txt')));
fullLog += section('Slither Security Reports', aggregateDir('/app/logs/slither', f => f.endsWith('.txt') || f.endsWith('.json')));
fullLog += section('AI Summaries and Reports', aggregateDir('/app/logs/reports', f => f.endsWith('.md') || f.endsWith('.txt')));
fullLog += section('Other Logs', aggregateDir('/app/logs', f => f.endsWith('.log') && !f.includes('evm-test.log')));

fullLog += section('Tool Run Confirmation', `
The following tools' logs were aggregated for ${contractName}:
- Testing: Foundry (all files in /app/logs/foundry starting with ${contractName}), coverage (all files in /app/logs/coverage starting with ${contractName})
- Security: Slither (all files in /app/logs/slither starting with ${contractName})
- AI/Manual reports: All .md/.txt in /app/logs/reports starting with ${contractName}
- Other specific tool logs (excluding verbose container procedure logs)
If any section above says "_No output found._", that log was missing or the tool did not run.
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
