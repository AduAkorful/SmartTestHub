const fs = require('fs');
const path = require('path');
const axios = require('axios');

const reportsDir = '/app/logs/reports';
const outputFile = '/app/logs/reports/complete-contracts-report.md';

if (!fs.existsSync(reportsDir)) {
  console.error("Reports directory does not exist:", reportsDir);
  process.exit(1);
}

const files = fs.readdirSync(reportsDir)
  .filter(f => f.endsWith('.md') || f.endsWith('.txt'))
  .map(f => path.join(reportsDir, f));

if (files.length === 0) {
  console.log("No report files found in", reportsDir);
  fs.writeFileSync(outputFile, "# No reports found to summarize.\n");
  process.exit(0);
}

let aggregated = '';
for (const file of files) {
  aggregated += `\n\n## File: ${path.basename(file)}\n`;
  aggregated += fs.readFileSync(file, 'utf8');
}

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
