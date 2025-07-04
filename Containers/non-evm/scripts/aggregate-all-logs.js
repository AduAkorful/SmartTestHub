const fs = require('fs');
const path = require('path');

const reportsDir = '/app/logs/reports';
const summarySuffix = '_report.md';
const outputFile = path.join(reportsDir, 'complete-contracts-report.md');

const summaries = fs.readdirSync(reportsDir)
  .filter(f => f.endsWith(summarySuffix));

let output = `# Complete Smart Contract Testing & Analysis Report (Solana/Non-EVM)\n\nGenerated: ${new Date().toISOString()}\n\n`;

for (const file of summaries) {
  const fullPath = path.join(reportsDir, file);
  const content = fs.readFileSync(fullPath, 'utf-8');
  const contractName = file.replace(summarySuffix, '');

  // --- Overview
  const overview = content.match(/## Overview[\s\S]*?(?=\n## |\n# |$)/);
  output += `## Contract: ${contractName}\n\n`;
  if (overview) output += `### Overview\n${overview[0].replace('## Overview','').trim()}\n\n`;

  // --- Build Status
  const build = content.match(/## Build Status[\s\S]*?(?=\n## |\n# |$)/);
  if (build) output += `### Build Status\n${build[0].replace('## Build Status','').trim()}\n\n`;

  // --- Test Results
  const testResults = content.match(/## Test Results[\s\S]*?(?=\n## |\n# |$)/);
  if (testResults) output += `### Test Results\n${testResults[0].replace('## Test Results','').trim()}\n\n`;

  // --- Security Analysis
  const security = content.match(/## Security Analysis[\s\S]*?(?=\n## |\n# |$)/);
  if (security) output += `### Security Analysis\n${security[0].replace('## Security Analysis','').trim()}\n\n`;

  // --- Performance Analysis
  const performance = content.match(/## Performance Analysis[\s\S]*?(?=\n## |\n# |$)/);
  if (performance) output += `### Performance Analysis\n${performance[0].replace('## Performance Analysis','').trim()}\n\n`;

  // --- Recommendations
  const recommendations = content.match(/## Recommendations[\s\S]*?(?=\n## |\n# |$)/);
  if (recommendations) output += `### Recommendations\n${recommendations[0].replace('## Recommendations','').trim()}\n\n`;

  output += `---\n\n`;
}

fs.writeFileSync(outputFile, output);
console.log(`Aggregated report created at ${outputFile}`);
