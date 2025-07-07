const fs = require('fs');
const path = require('path');
const axios = require('axios');

const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const GEMINI_MODEL = 'gemini-2.5-pro';
const GEMINI_URL = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

const reportsDir = '/app/logs/reports';
const outputFile = '/app/logs/reports/complete-contracts-report.md';

console.log("Starting aggregation...");

// Check if API key is present
if (!GEMINI_API_KEY) {
  console.error("Error: GEMINI_API_KEY environment variable not set.");
  process.exit(1);
}

// Check if reports directory exists
if (!fs.existsSync(reportsDir)) {
  console.error("Reports directory does not exist:", reportsDir);
  process.exit(1);
}

// Collect all report files
const files = fs.readdirSync(reportsDir)
  .filter(f => f.endsWith('.md') || f.endsWith('.txt'))
  .map(f => path.join(reportsDir, f));

if (files.length === 0) {
  console.log("No report files found in", reportsDir);
  fs.writeFileSync(outputFile, "# No reports found to summarize.\n");
  console.log("Wrote fallback report to", outputFile);
  process.exit(0);
}

// Aggregate content
let aggregated = '';
for (const file of files) {
  console.log("Reading:", file);
  aggregated += `\n\n## File: ${path.basename(file)}\n`;
  aggregated += fs.readFileSync(file, 'utf8');
}

console.log("Aggregated content length:", aggregated.length);

const prompt = `
You are an expert smart contract developer and security auditor.
Given the following smart contract analysis report, perform these tasks:
- Organize the report into clear, logical sections (e.g., Compilation, Tests, Security, Size).
- Rewrite the content to be clear, concise, and useful for developers.
- For each error, warning, or failed test, provide actionable insights or suggestions to help resolve the issue.
- For security findings, explain the risks and recommend best practices or code changes.
- Highlight important information using bullet points or tables where helpful.
- Ensure your summary is comprehensive but easy to read.

Report to analyze:
${aggregated}
`;

async function enhanceReport() {
  try {
    console.log("Sending request to Gemini API...");
    const response = await axios.post(
      GEMINI_URL,
      {
        contents: [
          {
            parts: [{ text: prompt }]
          }
        ]
      },
      {
        headers: {
          "Content-Type": "application/json",
          "X-goog-api-key": GEMINI_API_KEY
        }
      }
    );

    if (
      !response.data ||
      !response.data.candidates ||
      !response.data.candidates[0] ||
      !response.data.candidates[0].content ||
      !response.data.candidates[0].content.parts ||
      !response.data.candidates[0].content.parts[0] ||
      !response.data.candidates[0].content.parts[0].text
    ) {
      throw new Error("Malformed response from Gemini API");
    }

    const aiSummary = response.data.candidates[0].content.parts[0].text;
    fs.writeFileSync(outputFile, aiSummary);
    console.log("AI-enhanced report written to", outputFile);
  } catch (err) {
    console.error("AI enhancement failed, writing raw report.", err?.message || err);
    fs.writeFileSync(outputFile, aggregated);
    console.log("Raw report written to", outputFile);
  }
}

enhanceReport();
