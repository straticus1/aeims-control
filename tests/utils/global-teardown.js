// global-teardown.js
const fs = require('fs-extra');
const path = require('path');

async function globalTeardown(config) {
  console.log('\n🏁 Starting AEIMS UI Test Suite Teardown...');

  try {
    const resultsDir = path.join(__dirname, '..', 'test-results');
    const metadataPath = path.join(resultsDir, 'test-metadata.json');

    if (await fs.pathExists(metadataPath)) {
      const metadata = await fs.readJson(metadataPath);
      metadata.endTime = new Date().toISOString();

      const startTime = new Date(metadata.startTime);
      const endTime = new Date(metadata.endTime);
      metadata.duration = {
        totalMs: endTime - startTime,
        readable: formatDuration(endTime - startTime)
      };

      await fs.writeJson(metadataPath, metadata, { spaces: 2 });

      console.log(`⏱️  Total test duration: ${metadata.duration.readable}`);
      console.log(`📁 Test results saved to: ${resultsDir}`);
    }

    // Generate summary report
    await generateSummaryReport(resultsDir);

  } catch (error) {
    console.error('❌ Error during teardown:', error.message);
  }

  console.log('✅ Teardown complete!\n');
}

function formatDuration(ms) {
  const seconds = Math.floor(ms / 1000);
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);

  if (hours > 0) {
    return `${hours}h ${minutes % 60}m ${seconds % 60}s`;
  } else if (minutes > 0) {
    return `${minutes}m ${seconds % 60}s`;
  } else {
    return `${seconds}s`;
  }
}

async function generateSummaryReport(resultsDir) {
  try {
    const resultsJsonPath = path.join(resultsDir, 'results.json');
    if (await fs.pathExists(resultsJsonPath)) {
      const results = await fs.readJson(resultsJsonPath);

      const summary = {
        total: results.stats?.total || 0,
        passed: results.stats?.passed || 0,
        failed: results.stats?.failed || 0,
        skipped: results.stats?.skipped || 0,
        flaky: results.stats?.flaky || 0
      };

      const summaryPath = path.join(resultsDir, 'summary.json');
      await fs.writeJson(summaryPath, summary, { spaces: 2 });

      console.log('📊 Test Summary:');
      console.log(`   Total: ${summary.total}`);
      console.log(`   Passed: ${summary.passed}`);
      console.log(`   Failed: ${summary.failed}`);
      console.log(`   Skipped: ${summary.skipped}`);
      if (summary.flaky > 0) {
        console.log(`   Flaky: ${summary.flaky}`);
      }
    }
  } catch (error) {
    console.log('⚠️  Could not generate summary report:', error.message);
  }
}

module.exports = globalTeardown;