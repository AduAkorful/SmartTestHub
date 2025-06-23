const fs = require('fs');
const path = require('path');

const reportsDir = '/app/logs/reports';
const summaryPrefix = 'test-summary-';
const outputFile = path.join(reportsDir, 'complete-contracts-report.md');

const summaries = fs.readdirSync(reportsDir)
  .filter(f => f.startsWith(summaryPrefix) && f.endsWith('.md'));

let output = `# Complete Smart Contract Testing & Analysis Report\n\nGenerated: ${new Date().toISOString()}\n\n`;

for (const file of summaries) {
  const fullPath = path.join(reportsDir, file);
  const content = fs.readFileSync(fullPath, 'utf-8');
  const contractName = file.replace(summaryPrefix, '').replace('.md', '');

  // --- Contract Information
  const info = content.match(/## Contract Information[\s\S]*?(?=\n## |\n# |$)/);
  output += `## Contract: ${contractName}\n\n`;
  if (info) output += `### Contract Information\n${info[0].replace('## Contract Information','').trim()}\n\n`;

  // --- Compilation result
  const compilation = content.match(/- \*\*Compilation\*\*: (.*)/);
  output += `### Compilation Result\n`;
  if (compilation) output += `${compilation[1].trim()}\n\n`;

  // --- Test results (extract each test's result line)
  output += `### Foundry Test Results\n`;
  const foundryTestBlock = content.match(/Ran [\s\S]+?(?=Wrote LCOV|$)/);
  if (foundryTestBlock) {
    // Show only PASS/FAIL lines and suite summary
    const lines = foundryTestBlock[0].split('\n')
      .filter(line => line.match(/^\[(PASS|FAIL)\]/) || line.match(/Suite result:/) || line.match(/tests? passed|tests? failed/));
    if (lines.length > 0) output += lines.join('\n') + '\n\n';
    else output += '_No test results found._\n\n';
  } else {
    output += '_No test results found._\n\n';
  }

  // --- Security Analysis (extract Slither findings, not just pass/fail)
  output += `### Security Analysis (Slither)\n`;
  const slitherReportFile = path.join('/app/logs/slither', `${contractName}-report.txt`);
  if (fs.existsSync(slitherReportFile)) {
    const slitherLines = fs.readFileSync(slitherReportFile, 'utf-8')
      .split('\n')
      .filter(line =>
        line.match(/INFO:Detectors:/) ||
        line.match(/should be constant/) ||
        line.match(/should be immutable/) ||
        line.match(/too many digits/) ||
        line.match(/contains known severe issues/) ||
        line.match(/Reference:/)
      );
    if (slitherLines.length > 0) {
      output += slitherLines.join('\n') + '\n\n';
    } else {
      output += '_No actionable Slither findings._\n\n';
    }
  } else {
    output += '_No Slither report found._\n\n';
  }

  // --- Simple Security Checks (actionable)
  output += `### Simple Security Checks\n`;
  const highlights = content.match(/Simple Security Checks:[\s\S]*?(?=\n\n|\n# |$)/);
  if (highlights) {
    // Show only the checks with ⚠️ or ❌
    const lines = highlights[0].split('\n').filter(line =>
      line.includes('⚠️') || line.includes('❌') || line.includes('avoid')
    );
    if (lines.length > 0) output += lines.join('\n') + '\n\n';
    else output += '_No critical issues detected._\n\n';
  } else {
    output += '_No security check summary found._\n\n';
  }

  // --- Contract Size (warn if near or over EIP-170)
  output += `### Contract Size\n`;
  const sizeFile = path.join(reportsDir, `${contractName}-size.txt`);
  if (fs.existsSync(sizeFile)) {
    const sizeText = fs.readFileSync(sizeFile, 'utf-8');
    const statusLine = sizeText.split('\n').find(l => l.includes('Status:'));
    if (statusLine && statusLine.includes('Exceeds')) {
      output += `**Warning:** Contract size exceeds EIP-170 limit!\n${sizeText}\n\n`;
    } else {
      output += sizeText + '\n\n';
    }
  } else {
    output += '_No contract size information._\n\n';
  }

  output += `---\n\n`;
}

fs.writeFileSync(outputFile, output);
console.log(`Aggregated report written to ${outputFile}`);
