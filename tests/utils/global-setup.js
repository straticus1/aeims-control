// global-setup.js
const fs = require('fs-extra');
const path = require('path');

async function globalSetup(config) {
  console.log('🚀 Starting AEIMS UI Test Suite Setup...');

  // Ensure test results directory exists
  const resultsDir = path.join(__dirname, '..', 'test-results');
  await fs.ensureDir(resultsDir);
  await fs.ensureDir(path.join(resultsDir, 'screenshots'));
  await fs.ensureDir(path.join(resultsDir, 'artifacts'));

  // Create test run metadata
  const testRunId = new Date().toISOString().replace(/[:.]/g, '-');
  const metadata = {
    testRunId,
    startTime: new Date().toISOString(),
    baseURL: config.use?.baseURL || 'https://www.aeims.app',
    browsers: config.projects?.map(p => p.name) || [],
    testDir: config.testDir || './tests'
  };

  await fs.writeJson(path.join(resultsDir, 'test-metadata.json'), metadata, { spaces: 2 });

  console.log(`📋 Test Run ID: ${testRunId}`);
  console.log(`🌐 Base URL: ${metadata.baseURL}`);
  console.log(`🔧 Testing ${metadata.browsers.length} browser configurations`);
  console.log('✅ Setup complete!\n');
}

module.exports = globalSetup;