const fs = require('fs');
const path = require('path');

// Directories to scan
const DIRS = {
  summary: 'logs/reports',
  foundry: 'logs/foundry',
  slither: 'logs/slither',
  analysis: 'logs/reports',
  size: 'logs/reports',
  evm: 'logs',
  coverage: 'logs/coverage'
};

// Utility: Get latest file in a dir matching a pattern
function getLatestFile(dir, pattern) {
  if (!fs.existsSync(dir)) return null;
  const files = fs.readdirSync(dir)
    .filter(f => f.match(pattern))
    .map(f => ({file: f, time: fs.statSync(path.join(dir, f)).mtime.getTime()}))
    .sort((a, b) => b.time - a.time);
  return files.length > 0 ? path.join(dir, files[0].file) : null;
}

// Utility: Read file or return message
function safeRead(file) {
  try {
    return fs.readFileSync(file, 'utf8');
  } catch (err) {
    return `Could not read ${file}: ${err.message}`;
  }
}

// Find all contracts with summary files
const summaries = fs.existsSync(DIRS.summary)
  ? fs.readdirSync(DIRS.summary).filter(f => f.startsWith('test-summary-') && f.endsWith('.md'))
  : [];

let report = `# Complete Smart Contract Testing & Analysis Report\n\n`;
report += `Generated: ${new Date().toISOString()}\n\n`;

if (summaries.length === 0) {
  report += '_No contract summaries found._\n';
} else {
  summaries.forEach(summaryFile => {
    const contractName = summaryFile.replace('test-summary-', '').replace('.md', '');
    report += `## Contract: ${contractName}\n\n`;

    // Add summary
    const summaryPath = path.join(DIRS.summary, summaryFile);
    report += `### Summary\n`;
    report += safeRead(summaryPath) + '\n\n';

    // Foundry Test Output
    const foundryJson = getLatestFile(DIRS.foundry, new RegExp(`${contractName}.*\\.json$`)) ||
                        getLatestFile(DIRS.foundry, /\.json$/); // fallback
    if (foundryJson) {
      report += `### Foundry Test Output\n\`\`\`json\n${safeRead(foundryJson)}\n\`\`\`\n\n`;
    }

    // Coverage
    const coverageFile = getLatestFile(DIRS.coverage, new RegExp(`${contractName}.*\\.info$`)) ||
                         getLatestFile(DIRS.coverage, /\.info$/);
    if (coverageFile) {
      report += `### Coverage Report (LCOV)\n\`\`\`text\n${safeRead(coverageFile)}\n\`\`\`\n\n`;
    }

    // Slither
    const slitherReport = getLatestFile(DIRS.slither, new RegExp(`${contractName}.*\\.txt$`)) ||
                          getLatestFile(DIRS.slither, /\.txt$/);
    if (slitherReport) {
      report += `### Security Analysis (Slither)\n\`\`\`text\n${safeRead(slitherReport)}\n\`\`\`\n\n`;
    }

    // Custom Analysis
    const analysisFile = getLatestFile(DIRS.analysis, new RegExp(`${contractName}-analysis\\.txt$`));
    if (analysisFile) {
      report += `### Custom Contract Analysis\n\`\`\`text\n${safeRead(analysisFile)}\n\`\`\`\n\n`;
    }

    // Size Analysis
    const sizeFile = getLatestFile(DIRS.size, new RegExp(`${contractName}-size\\.txt$`));
    if (sizeFile) {
      report += `### Contract Size Analysis\n\`\`\`text\n${safeRead(sizeFile)}\n\`\`\`\n\n`;
    }

    // EVM process log (general / not per-contract)
    const evmLog = getLatestFile(DIRS.evm, /^evm-test\.log$/);
    if (evmLog) {
      report += `### Full EVM Process Log\n\`\`\`text\n${safeRead(evmLog)}\n\`\`\`\n\n`;
    }

    report += `---\n\n`;
  });
}

// Write the aggregated report
const outFile = 'logs/reports/complete-contracts-report.md';
fs.writeFileSync(outFile, report);
console.log(`Aggregated report written to ${outFile}`);
