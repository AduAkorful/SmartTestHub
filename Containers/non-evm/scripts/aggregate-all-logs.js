const fs = require('fs');
const path = require('path');
const axios = require('axios');

// Directory containing contract reports/logs
const reportsDir = '/app/logs/reports';

// Output file
const outputFile = '/app/logs/reports/complete-contracts-report.md';

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

// IMPROVED, DETAILED PROMPT
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

// POST to Ollama API
async function enhanceReport() {
  try {
    const response = await axios.post(
      'http://ai-log-processor:11434/v1/chat/completions',
      {
        model: "phi3:mini",
        messages: [{ role: "user", content: prompt }],
        max_tokens: 2048
      }
    );
    const aiSummary = response.data.choices[0].message.content;
    fs.writeFileSync(outputFile, aiSummary);
    console.log("AI-enhanced report written to", outputFile);
  } catch (err) {
    console.error("AI enhancement failed, writing raw report.", err?.message || err);
    fs.writeFileSync(outputFile, aggregated);
  }
}

enhanceReport();
