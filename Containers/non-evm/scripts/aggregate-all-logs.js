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

// CHANGE: output file
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

// Only aggregate logs for this contract
function aggregateDir(dir, filter = () => true) {
  return tryList(dir, f => f.startsWith(contractName) && filter(f))
    .map(f => `### File: ${f}\n` + tryRead(path.join(dir, f)))
    .join('\n\n');
}

function aggregateTestResults() {
  const dir = '/app/logs/reports';
  const files = [
    `${contractName}-cargo-test.log`,
    `${contractName}-anchor-test.log`,
    `${contractName}-pytest.log`
  ];
  const contents = files
    .map(f => path.join(dir, f))
    .filter(p => fs.existsSync(p))
    .map(p => `### File: ${path.basename(p)}\n` + tryRead(p))
    .join('\n\n');
  return contents || '_No output found._';
}

function aggregateCoverage() {
  const dir = '/app/logs/coverage';
  const candidates = [
    `${contractName}-coverage.log`,
    `${contractName}-coverage.html`,
    `${contractName}-coverage.xml`,
    `${contractName}-lcov.info`,
    // fallback names used by tarpaulin
    'tarpaulin-report.html',
    'cobertura.xml',
    'lcov.info'
  ];
  const contents = candidates
    .map(f => path.join(dir, f))
    .filter(p => fs.existsSync(p))
    .map(p => `### File: ${path.basename(p)}\n` + tryRead(p))
    .join('\n\n');
  return contents || '_No output found._';
}

const mainReportNote = `Note: After aggregation, only the main AI-enhanced report (${contractName}-report.txt) is retained in /app/logs/reports and /app/contracts/${contractName} for this contract.`;

let fullLog = '';
// Removed: Docker process logs (test.log) to reduce length
const secAudit = section('Security Audit (Cargo Audit)', aggregateDir('/app/logs/security', f => f.endsWith('-cargo-audit.log')));
const secClippy = section('Security Lint (Clippy)', aggregateDir('/app/logs/security', f => f.endsWith('-clippy.log')));
const testRes = section('Test Results', aggregateTestResults());
const covRes = section('Coverage Reports (Tarpaulin)', aggregateCoverage());
const benches = section('Performance Benchmarks', aggregateDir('/app/logs/benchmarks', f => f.endsWith('-benchmarks.log')));
const binSize = section('Binary Size Analysis', aggregateDir('/app/logs/analysis', f => f.endsWith('-binary-size.log')));
const perfLog = section('Performance Log', tryRead('/app/logs/analysis/performance.log'));
const summary = section('Comprehensive Summary', aggregateDir('/app/logs/reports', f => f.endsWith('-summary.log')));
const docs = section('AI/Manual Reports', aggregateDir('/app/logs/reports', f => f.endsWith('.md') || f.endsWith('.txt')));

fullLog += secAudit + secClippy + testRes + covRes + benches + binSize + perfLog + summary + docs;

// Summarize only what was included, without stating absences
const present = [];
if (secAudit) present.push('Cargo Audit');
if (secClippy) present.push('Clippy');
if (testRes) present.push('Tests');
if (covRes) present.push('Coverage');
if (benches) present.push('Benchmarks');
if (binSize) present.push('Binary Size');
if (perfLog) present.push('Performance Log');
if (summary) present.push('Summary');
if (docs) present.push('AI/Manual Reports');
if (present.length) {
  fullLog += `\n\n## Tool Inputs Included\n\n${present.map(p => `- ${p}`).join('\n')}`;
}

const prompt = `
You are an expert smart contract auditor specializing in Solana/Rust contracts.
You are given the raw logs and reports from a full smart contract testing and analysis pipeline.

IMPORTANT OUTPUT RULES:
- Use the following section titles and order WHEN THERE IS CONTENT for them.
- Only write about evidence present in the logs below. DO NOT mention or infer missing/absent data.
- Never write phrases like "No output found", "not available", "skipped", or "missing".
- Omit any subsection or whole section if there is no evidence for it in the logs.

Sections (include only if applicable):
## 1. OVERVIEW
- Contract Information; Analysis Status; Summary of tools and results (from present logs only)

## 2. TESTING
- Test execution results; Rust compilation/build results; Program test results; Coverage metrics; Recommendations

## 3. SECURITY
- Security summary; Findings; Results from security tools; Best practices

## 4. CODE QUALITY
- Linting results; Metrics; Standards compliance; Improvements

## 5. PERFORMANCE
- Binary size; Build/test timing; Execution efficiency; Optimization recommendations

## 6. AI SUMMARY
- Overall Assessment; Risk; Deployment Readiness; Key Findings; Priority Actions; Recommendations

Analysis Guidelines:
- Extract specific metrics directly from the logs. Do not speculate.
- Provide actionable recommendations grounded in the observed outputs.

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
