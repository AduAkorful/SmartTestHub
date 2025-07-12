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
  return tryList(dir, f => (f === `${contractName}-report.md` || f.startsWith(`${contractName}-`)) && filter(f))
    .map(f => `### File: ${f}\n` + tryRead(path.join(dir, f)))
    .join('\n\n');
}

let fullLog = '';
fullLog += section('Non-EVM Container Procedure Log', tryRead('/app/logs/test.log'));
fullLog += section('Security Audit (Cargo Audit)', aggregateDir('/app/logs/security', f => f.endsWith('-cargo-audit.log')));
fullLog += section('Security Lint (Clippy)', aggregateDir('/app/logs/security', f => f.endsWith('-clippy.log')));
fullLog += section('Coverage Reports', aggregateDir('/app/logs/coverage', f => f.endsWith('.html')));
fullLog += section('Performance Benchmarks', aggregateDir('/app/logs/benchmarks', () => true));
fullLog += section('AI/Manual Reports', aggregateDir('/app/logs/reports', f => f.endsWith('.md') || f.endsWith('.txt')));

fullLog += section('Tool Run Confirmation', `
The following tools' logs were aggregated for ${contractName}:
- Compilation: test.log, build logs
- Testing: test.log, coverage (all files in /app/logs/coverage starting with ${contractName})
- Security: Cargo Audit and Clippy (all files in /app/logs/security starting with ${contractName})
- Performance: All logs in /app/logs/benchmarks starting with ${contractName}
- AI/Manual reports: All .md/.txt in /app/logs/reports starting with ${contractName}
If any section above says "_No output found._", that log was missing or the tool did not run.
`);

const prompt = `
You are an expert smart contract auditor (Solana/Rust context).
You are given the **raw logs and reports** from a full smart contract testing and analysis pipeline (see below).
- Organize the output into logical sections: Compilation, Tests, Security, Coverage, Performance, AI/Manual summaries.
- For each tool, summarize key findings in clear, actionable language.
- For each error, warning, or failed test, provide insights to help resolve the issue.
- For security findings, explain risks and recommend best practices or code changes.
- If any tool appears missing, failed, or incomplete, clearly indicate this.
- Highlight important information with bullet points or tables.
- Include a "Tool Run Confirmation" section stating which logs were present and included.
- Make the summary comprehensive, structured, and developer-friendly.

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
