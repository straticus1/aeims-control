#!/usr/bin/env node

/**
 * Reconciliation System Integration Tests
 *
 * Tests all reconciliation components to ensure they work correctly.
 */

const assert = require('assert');
const ManifestTracker = require('../lib/manifest-tracker');
const DriftDetector = require('../lib/drift-detector');
const VersionLockManager = require('../lib/version-lock');
const fs = require('fs').promises;

const COLORS = {
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  reset: '\x1b[0m'
};

class ReconciliationTests {
  constructor() {
    this.manifestTracker = new ManifestTracker();
    this.driftDetector = new DriftDetector();
    this.versionLock = new VersionLockManager();
    this.passed = 0;
    this.failed = 0;
    this.testService = `test-service-${Date.now()}`;
  }

  /**
   * Run test with error handling
   */
  async test(name, fn) {
    process.stdout.write(`Testing ${name}... `);

    try {
      await fn();
      console.log(`${COLORS.green}✓ PASS${COLORS.reset}`);
      this.passed++;
    } catch (error) {
      console.log(`${COLORS.red}✗ FAIL${COLORS.reset}`);
      console.log(`  ${error.message}`);
      this.failed++;
    }
  }

  /**
   * Test: Manifest tracking
   */
  async testManifestTracking() {
    await this.test('Manifest tracker initialization', async () => {
      await this.manifestTracker.initialize();
      assert.ok(true, 'Tracker initialized');
    });

    await this.test('Create deployment manifest', async () => {
      const manifest = await this.manifestTracker.createManifest({
        serviceName: this.testService,
        version: '1.0.0',
        imageName: 'test-image',
        imageTag: 'latest',
        environment: 'test',
        config: {
          TEST_VAR: 'test-value'
        },
        taskDefinitionArn: 'arn:aws:ecs:test',
        desiredCount: 2
      });

      assert.ok(manifest.deploymentId, 'Deployment ID created');
      assert.equal(manifest.version, '1.0.0', 'Version matches');
      assert.equal(manifest.serviceName, this.testService, 'Service name matches');
    });

    await this.test('Retrieve current state', async () => {
      const state = await this.manifestTracker.getCurrentState(this.testService);

      assert.ok(state, 'State retrieved');
      assert.equal(state.version, '1.0.0', 'Version matches');
      assert.equal(state.config.data.TEST_VAR, 'test-value', 'Config matches');
    });

    await this.test('Create second deployment', async () => {
      const manifest = await this.manifestTracker.createManifest({
        serviceName: this.testService,
        version: '2.0.0',
        imageName: 'test-image',
        imageTag: 'v2',
        environment: 'test',
        config: {
          TEST_VAR: 'new-value'
        },
        taskDefinitionArn: 'arn:aws:ecs:test:v2',
        desiredCount: 3
      });

      assert.equal(manifest.version, '2.0.0', 'New version created');
    });

    await this.test('View deployment history', async () => {
      const history = await this.manifestTracker.getHistory(this.testService);

      assert.ok(Array.isArray(history), 'History is array');
      assert.equal(history.length, 2, 'Has 2 deployments');
      assert.equal(history[0].version, '2.0.0', 'Latest is first');
      assert.equal(history[1].version, '1.0.0', 'Oldest is last');
    });

    await this.test('Create backup', async () => {
      const backup = await this.manifestTracker.createBackup(this.testService);

      assert.ok(backup, 'Backup created');
      assert.ok(backup.backupId, 'Backup ID exists');
      assert.ok(backup.state, 'Backup has state');
    });

    await this.test('List backups', async () => {
      const backups = await this.manifestTracker.listBackups(this.testService);

      assert.ok(Array.isArray(backups), 'Backups is array');
      assert.ok(backups.length > 0, 'Has backups');
    });
  }

  /**
   * Test: Config hashing
   */
  async testConfigHashing() {
    await this.test('Hash config consistency', async () => {
      const config1 = { a: 1, b: 2, c: 3 };
      const config2 = { c: 3, b: 2, a: 1 }; // Same but different order

      const hash1 = this.manifestTracker.hashConfig(config1);
      const hash2 = this.manifestTracker.hashConfig(config2);

      assert.equal(hash1, hash2, 'Hashes match regardless of key order');
    });

    await this.test('Hash config changes', async () => {
      const config1 = { a: 1, b: 2 };
      const config2 = { a: 1, b: 3 }; // Different value

      const hash1 = this.manifestTracker.hashConfig(config1);
      const hash2 = this.manifestTracker.hashConfig(config2);

      assert.notEqual(hash1, hash2, 'Hashes differ for different configs');
    });
  }

  /**
   * Test: Drift detection (mock)
   */
  async testDriftDetection() {
    await this.test('Detect manifest drift', async () => {
      const currentState = await this.manifestTracker.getCurrentState(this.testService);

      const desiredState = {
        image: {
          tag: 'v3', // Different from current
          digest: null
        },
        config: {
          data: {
            TEST_VAR: 'different-value' // Different from current
          }
        },
        aws: {
          desiredCount: 5 // Different from current
        }
      };

      const drift = await this.manifestTracker.detectDrift(this.testService, desiredState);

      assert.equal(drift.hasDrift, true, 'Drift detected');
      assert.ok(drift.drifts.length > 0, 'Has drift items');
    });

    await this.test('No drift when states match', async () => {
      const currentState = await this.manifestTracker.getCurrentState(this.testService);

      const desiredState = {
        image: {
          tag: currentState.image.tag,
          digest: currentState.image.digest
        },
        config: {
          data: currentState.config.data
        },
        aws: {
          desiredCount: currentState.aws.desiredCount
        }
      };

      const drift = await this.manifestTracker.detectDrift(this.testService, desiredState);

      assert.equal(drift.hasDrift, false, 'No drift detected');
      assert.equal(drift.drifts.length, 0, 'No drift items');
    });
  }

  /**
   * Test: Version locking
   */
  async testVersionLocking() {
    await this.test('Lock service version', async () => {
      const locked = await this.versionLock.lockService(this.testService, {
        imageName: 'test-image',
        imageTag: 'v1.0',
        version: '1.0.0'
      });

      assert.ok(locked, 'Service locked');
      assert.equal(locked.version, '1.0.0', 'Version locked');
    });

    await this.test('Retrieve version lock', async () => {
      const lock = await this.versionLock.getLock();

      assert.ok(lock.services[this.testService], 'Service in lock');
      assert.equal(lock.services[this.testService].version, '1.0.0', 'Version matches');
    });

    await this.test('Lock file persistence', async () => {
      const lock1 = await this.versionLock.getLock();
      const versionLock2 = new VersionLockManager();
      const lock2 = await versionLock2.getLock();

      assert.equal(
        JSON.stringify(lock1.services),
        JSON.stringify(lock2.services),
        'Lock persists across instances'
      );
    });
  }

  /**
   * Test: Rollback
   */
  async testRollback() {
    await this.test('Rollback to previous deployment', async () => {
      const history = await this.manifestTracker.getHistory(this.testService);
      const oldestDeployment = history[history.length - 1];

      const rolled = await this.manifestTracker.rollback(
        this.testService,
        oldestDeployment.deploymentId
      );

      assert.equal(rolled.deploymentId, oldestDeployment.deploymentId, 'Rolled back');
      assert.equal(rolled.version, oldestDeployment.version, 'Version rolled back');
    });

    await this.test('Current state after rollback', async () => {
      const history = await this.manifestTracker.getHistory(this.testService);
      const oldestDeployment = history[history.length - 1];
      const currentState = await this.manifestTracker.getCurrentState(this.testService);

      assert.equal(currentState.version, oldestDeployment.version, 'State matches rollback target');
    });
  }

  /**
   * Test: Summary and reporting
   */
  async testSummary() {
    await this.test('Get deployment summary', async () => {
      const summary = await this.manifestTracker.getSummary();

      assert.ok(Array.isArray(summary), 'Summary is array');

      const testSummary = summary.find(s => s.serviceName === this.testService);
      assert.ok(testSummary, 'Test service in summary');
      assert.ok(testSummary.currentDeployment, 'Has current deployment');
      assert.ok(testSummary.recentDeployments > 0, 'Has deployment history');
    });
  }

  /**
   * Run all tests
   */
  async runAll() {
    console.log('\n' + '='.repeat(70));
    console.log('AEIMS RECONCILIATION SYSTEM - INTEGRATION TESTS');
    console.log('='.repeat(70) + '\n');

    try {
      await this.testManifestTracking();
      await this.testConfigHashing();
      await this.testDriftDetection();
      await this.testVersionLocking();
      await this.testRollback();
      await this.testSummary();
    } catch (error) {
      console.error(`\n${COLORS.red}Fatal test error:${COLORS.reset}`, error.message);
    }

    // Print summary
    console.log('\n' + '='.repeat(70));
    console.log('TEST RESULTS');
    console.log('='.repeat(70));
    console.log(`${COLORS.green}Passed: ${this.passed}${COLORS.reset}`);

    if (this.failed > 0) {
      console.log(`${COLORS.red}Failed: ${this.failed}${COLORS.reset}`);
    }

    const total = this.passed + this.failed;
    const percentage = ((this.passed / total) * 100).toFixed(1);
    console.log(`Total: ${total}`);
    console.log(`Success Rate: ${percentage}%`);
    console.log('='.repeat(70) + '\n');

    // Cleanup
    console.log('Cleaning up test data...');
    await this.cleanup();

    return this.failed === 0;
  }

  /**
   * Cleanup test data
   */
  async cleanup() {
    try {
      // Remove test service from manifests
      const currentStatePath = require('path').join(
        this.manifestTracker.stateDir,
        `${this.testService}.current.json`
      );
      const historyPath = require('path').join(
        this.manifestTracker.stateDir,
        `${this.testService}.history.json`
      );

      await fs.unlink(currentStatePath).catch(() => {});
      await fs.unlink(historyPath).catch(() => {});

      // Remove test service from version lock
      const lock = await this.versionLock.getLock();
      delete lock.services[this.testService];
      await this.versionLock.saveLock(lock);

      // Remove test backups
      const backups = await this.manifestTracker.listBackups(this.testService);
      for (const backup of backups) {
        await fs.unlink(backup.backupPath).catch(() => {});
      }

      console.log('✓ Cleanup complete\n');
    } catch (error) {
      console.log(`⚠️  Cleanup warning: ${error.message}\n`);
    }
  }
}

// Run tests if executed directly
if (require.main === module) {
  const tests = new ReconciliationTests();

  tests.runAll().then(success => {
    process.exit(success ? 0 : 1);
  }).catch(error => {
    console.error('Test execution failed:', error);
    process.exit(1);
  });
}

module.exports = ReconciliationTests;
