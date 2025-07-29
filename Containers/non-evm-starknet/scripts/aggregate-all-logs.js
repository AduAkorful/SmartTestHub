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

const outputFile = `/app/logs/reports/${contractName}-report.md`;

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

const mainReportNote = `Note: After aggregation, only the main AI-enhanced report (${contractName}-report.md) is retained in /app/logs/reports and /app/contracts/${contractName} for this contract.`;

let fullLog = '';
fullLog += section('StarkNet Container Procedure Log', tryRead('/app/logs/test.log'));
fullLog += section('Lint (starknet-lint)', aggregateDir('/app/logs/security', f => f.endsWith('-lint.log')));
fullLog += section('Security (starknet-audit)', aggregateDir('/app/logs/security', f => f.endsWith('-audit.log')));
fullLog += section('Compilation Logs', aggregateDir('/app/logs', f => f.endsWith('-compile.log')));
fullLog += section('AI/Manual Reports', aggregateDir('/app/logs/reports', f => f.endsWith('.md') || f.endsWith('.txt')));
fullLog += section('Tool Run Confirmation', `
The following tools' logs were aggregated for ${contractName}:
- Compilation: test.log, compile logs
- Testing: test.log (pytest)
- Lint: starknet-lint (all files in /app/logs/security starting with ${contractName})
- Security: starknet-audit (all files in /app/logs/security starting with ${contractName})
- AI/Manual reports: All .md/.txt in /app/logs/reports starting with ${contractName}
If any section above says "_No output found._", that log was missing or the tool did not run.

${mainReportNote}
`);

const prompt = `
You are an expert smart contract auditor specializing in StarkNet/Cairo contracts.
You are given the **raw logs and reports** from a full smart contract testing and analysis pipeline.

**IMPORTANT: Structure your response in exactly these 6 sections in this order:**

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

**Analysis Guidelines:**
- Extract specific metrics from logs (file size, line counts, function counts, test numbers)
- Focus on Cairo-specific vulnerabilities and patterns
- Analyze Cairo compilation and bytecode efficiency
- Identify storage variable and event handling issues
- Provide actionable recommendations for StarkNet development
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
