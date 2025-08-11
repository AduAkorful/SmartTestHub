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
  if (!content || !content.trim()) return '';
  return `\n\n## ${title}\n\n${content}`;
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
  return contents;
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
  return contents;
}

const mainReportNote = `Note: After aggregation, only the main AI-enhanced report (${contractName}-report.txt) is retained in /app/logs/reports and /app/contracts/${contractName} for this contract.`;

let fullLog = '';
// Removed: Docker process logs (test.log) to reduce length
fullLog += section('Security Audit (Cargo Audit)', aggregateDir('/app/logs/security', f => f.endsWith('-cargo-audit.log')));
fullLog += section('Security Lint (Clippy)', aggregateDir('/app/logs/security', f => f.endsWith('-clippy.log')));
fullLog += section('Test Results', aggregateTestResults());
fullLog += section('Coverage Reports', aggregateCoverage());
fullLog += section('Performance Benchmarks', aggregateDir('/app/logs/benchmarks', f => f.endsWith('-benchmarks.log')));
fullLog += section('Binary Size Analysis', aggregateDir('/app/logs/analysis', f => f.endsWith('-binary-size.log')));
fullLog += section('Performance Log', tryRead('/app/logs/analysis/performance.log'));
fullLog += section('Comprehensive Summary', aggregateDir('/app/logs/reports', f => f.endsWith('-summary.log')));
fullLog += section('AI/Manual Reports', aggregateDir('/app/logs/reports', f => f.endsWith('.md') || f.endsWith('.txt')));

const includedTools = [];
if (aggregateCoverage()) includedTools.push('Coverage');
if (aggregateDir('/app/logs/security', f => f.endsWith('-cargo-audit.log'))) includedTools.push('Cargo Audit');
if (aggregateDir('/app/logs/security', f => f.endsWith('-clippy.log'))) includedTools.push('Clippy');
if (aggregateDir('/app/logs/benchmarks', f => f.endsWith('-benchmarks.log'))) includedTools.push('Benchmarks');
if (aggregateDir('/app/logs/reports', f => f.endsWith('-summary.log'))) includedTools.push('Summary');
if (aggregateTestResults()) includedTools.push('Tests');
fullLog += section('Tool Run Confirmation', `The following tools had logs for ${contractName}: ${includedTools.join(', ')}\n\n${mainReportNote}`);

const prompt = `
You are an expert smart contract auditor specializing in Solana/Rust contracts.
You are given the **raw logs and reports** from a full smart contract testing and analysis pipeline.

**IMPORTANT: Structure your response in exactly these 6 sections in this order:**

## 1. OVERVIEW
- Contract Information (file name, size, lines of code, contract type: Solana Rust)
- Analysis Status (Rust compilation, testing status, security status, coverage status)
- Summary of all tools that ran and their overall results

## 2. TESTING
- Test execution results (passed/failed/skipped counts)
- Rust compilation and build results
- Solana program test results
- Test coverage metrics and detailed test analysis
- Testing recommendations for Solana-specific scenarios

## 3. SECURITY
- Security Summary with vulnerability counts (Critical: X, High: X, Medium: X, Low: X)
- Security Score assessment (e.g., "Good security with minor issues - Address the identified vulnerabilities")
- Detailed vulnerability findings with Rust/Solana-specific security patterns
- Results from security tools (Cargo audit, Clippy, custom Solana analysis)
- Solana security best practices and account handling recommendations

## 4. CODE QUALITY
- Code quality score and overall assessment
- Rust linting results (Clippy errors, warnings, style issues)
- Rust code metrics (complexity, maintainability, documentation quality)
- Solana coding standards compliance and naming conventions
- Code improvement suggestions for Rust/Solana development

## 5. PERFORMANCE
- Rust Analysis (binary size, compilation performance, execution efficiency)
- Contract metrics (Rust file size, complexity, memory usage)
- Performance recommendations and Rust optimization opportunities
- Solana transaction cost analysis and compute unit efficiency

## 6. AI SUMMARY
- Overall Assessment (Excellent/Good/Fair/Poor)
- Risk Level (Low/Medium/High/Critical)
- Deployment Readiness (Ready/Ready with improvements/Not ready)
- Key Findings (main observations and Solana-specific issues)
- Priority Actions (most important next steps for Rust contracts)
- Recommendations (Solana best practices and improvements)

**Analysis Guidelines:**
- Extract specific metrics from logs (file size, line counts, test numbers, binary size)
- Focus on Rust/Solana-specific vulnerabilities and patterns
- Analyze Rust compilation efficiency and safety features
- Identify account handling and instruction processing issues
- Provide actionable recommendations for Solana development
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
