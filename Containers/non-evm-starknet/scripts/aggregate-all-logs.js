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
  const clean = (content || '').trim();
  if (!clean) return '';
  return `\n\n## ${title}\n\n${clean}`;
}
function aggregateDir(dir, filter = () => true) {
  return tryList(dir, f => f.startsWith(contractName) && filter(f))
    .map(f => `### File: ${f}\n` + tryRead(path.join(dir, f)))
    .join('\n\n');
}

const mainReportNote = `Note: After aggregation, only the main AI-enhanced report (${contractName}-report.txt) is retained in /app/logs/reports and /app/contracts/${contractName} for this contract.`;

let fullLog = '';
// Aggregate all tool outputs for StarkNet container
// Prefer contract-specific pytest log if present; fall back to container test.log
const contractPytestLog = tryRead(`/app/logs/reports/${contractName}-pytest.log`);
fullLog += section('PyTest Test Results', contractPytestLog || tryRead('/app/logs/test.log'));
fullLog += section('Flake8 Linting', tryRead(`/app/logs/security/${contractName}-flake8.log`));
fullLog += section('Security Analysis', tryRead(`/app/logs/security/${contractName}-bandit.log`));
fullLog += section('Cairo Compilation', tryRead(`/app/logs/${contractName}-compile.log`));
fullLog += section('Cairo Compile Status', tryRead(`/app/logs/${contractName}-compile.status`));
fullLog += section('Compiled Contract', tryRead(`/app/logs/${contractName}-compiled.json`));
fullLog += section('AI/Manual Reports', aggregateDir('/app/logs/reports', f => f.endsWith('.md') || f.endsWith('.txt')));
// Summarize only present inputs
const present = [];
if (contractPytestLog.trim() || tryRead('/app/logs/test.log').trim()) present.push('PyTest');
if (tryRead(`/app/logs/security/${contractName}-flake8.log`).trim()) present.push('Flake8');
if (tryRead(`/app/logs/security/${contractName}-bandit.log`).trim()) present.push('Security Analysis');
if (tryRead(`/app/logs/${contractName}-compile.log`).trim()) present.push('Cairo Compilation');
if (tryRead(`/app/logs/${contractName}-compile.status`).trim()) present.push('Compile Status');
if (tryRead(`/app/logs/${contractName}-compiled.json`).trim()) present.push('Compiled Contract');
if (present.length) {
  fullLog += section('Tool Inputs Included', present.map(p => `- ${p}`).join('\n'));
}

const prompt = `
You are an expert smart contract auditor specializing in StarkNet/Cairo contracts.
You are given the raw logs and reports from a full smart contract testing and analysis pipeline.

IMPORTANT OUTPUT RULES:
- Use the section titles below in order WHEN THERE IS CONTENT for them.
- Only write about evidence present in the logs. Do not mention missing/absent data.
- Never write phrases like "No output found", "not available", "skipped", or "missing". Omit empty sections entirely.

Sections (include only if applicable):

## 1. OVERVIEW
- Contract Information (file name, size, lines of code, contract type: StarkNet Cairo)
- Analysis Status (Cairo compilation, testing status, security status, coverage status)
- Summary of all tools that ran and their overall results

## 2. TESTING
- Test execution results (passed/failed/skipped counts)
- Cairo compilation test results
- Contract deployment test results
- Test coverage metrics and detailed test analysis
- Testing recommendations for StarkNet-specific scenarios

## 3. SECURITY
- Security Summary with vulnerability counts (Critical: X, High: X, Medium: X, Low: X)
- Security Score assessment (e.g., "Good security with minor issues - Address the identified vulnerabilities")
- Detailed vulnerability findings with Cairo-specific security patterns
- Results from security tools (Cairo security analysis, custom StarkNet patterns)
- StarkNet security best practices and storage pattern recommendations

## 4. CODE QUALITY
- Code quality score and overall assessment
- Cairo linting results (errors, warnings, style issues)
- Cairo code metrics (complexity, maintainability, documentation quality)
- StarkNet coding standards compliance and naming conventions
- Code improvement suggestions for Cairo development

## 5. PERFORMANCE
- Cairo Analysis (compiled bytecode size, complexity analysis, gas estimation)
- Contract metrics (Cairo file size, function count, storage efficiency)
- Performance recommendations and Cairo optimization opportunities
- StarkNet transaction cost analysis and proof generation efficiency

## 6. AI SUMMARY
- Overall Assessment (Excellent/Good/Fair/Poor)
- Risk Level (Low/Medium/High/Critical)
- Deployment Readiness (Ready/Ready with improvements/Not ready)
- Key Findings (main observations and StarkNet-specific issues)
- Priority Actions (most important next steps for Cairo contracts)
- Recommendations (StarkNet best practices and improvements)

Analysis Guidelines:
- Extract specific metrics only from present logs; avoid speculation.
- Provide actionable recommendations grounded in observed outputs.

Complete logs and reports:
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
