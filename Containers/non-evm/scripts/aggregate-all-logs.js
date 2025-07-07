require('dotenv').config({ path: '/app/.env' }); // Adjust path if needed

const fs = require('fs');
const path = require('path');
const axios = require('axios');

const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const GEMINI_MODEL = 'gemini-2.5-pro';
const GEMINI_URL = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

const reportsDir = '/app/logs/reports';
const outputFile = '/app/logs/reports/complete-contracts-report.md';

// Check if API key is present
if (!GEMINI_API_KEY) {
  console.error("Error: GEMINI_API_KEY environment variable not set.");
  process.exit(1);
}

// Collect all report files
const files = fs.readdirSync(reportsDir)
  .filter(f => f.endsWith('.md') || f.endsWith('.txt'))
  .map(f => path.join(reportsDir, f));

// Aggregate content
let aggregated = '';
for (const file of files) {
  aggregated += `\n\n## File: ${path.basename(file)}\n`;
  aggregated += fs.readFileSync(file, 'utf8');
}

const prompt = `
You are an expert Solana smart contract developer and security auditor.
Given the following Solana smart contract testing and analysis report, perform these tasks:
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
