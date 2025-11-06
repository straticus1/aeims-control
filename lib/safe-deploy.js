#!/usr/bin/env node

/**
 * Safe Deployment Wrapper
 *
 * Wraps deployment operations with safety checks:
 * - Pre-deployment drift detection
 * - Approval gates based on severity
 * - Backup creation
 * - Manifest tracking
 * - Version locking
 * - Post-deployment verification
 * - Automatic rollback on failure
 */

const DriftDetector = require('./drift-detector');
const ManifestTracker = require('./manifest-tracker');
const VersionLockManager = require('./version-lock');
const readline = require('readline');
const { execSync } = require('child_process');

class SafeDeploy {
  constructor(options = {}) {
    this.driftDetector = new DriftDetector();
    this.manifestTracker = new ManifestTracker();
    this.versionLock = new VersionLockManager();
    this.autoApprove = options.autoApprove || false;
    this.skipDriftCheck = options.skipDriftCheck || false;
    this.dryRun = options.dryRun || false;
    this.clusterName = options.clusterName || 'aeims-cluster-production';
  }

  /**
   * Ask for user confirmation
   */
  async askConfirmation(message, defaultYes = false) {
    if (this.autoApprove) {
      return true;
    }

    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout
    });

    const defaultPrompt = defaultYes ? '[Y/n]' : '[y/N]';

    return new Promise((resolve) => {
      rl.question(`${message} ${defaultPrompt}: `, (answer) => {
        rl.close();

        if (!answer) {
          resolve(defaultYes);
        } else {
          resolve(answer.toLowerCase() === 'yes' || answer.toLowerCase() === 'y');
        }
      });
    });
  }

  /**
   * Execute command safely
   */
  exec(command, description) {
    console.log(`\n🔧 ${description}`);

    if (this.dryRun) {
      console.log(`   [DRY RUN] Would execute: ${command}`);
      return '';
    }

    try {
      const result = execSync(command, { encoding: 'utf8', stdio: 'inherit' });
      console.log('   ✅ Success');
      return result;
    } catch (error) {
      console.error(`   ❌ Failed: ${error.message}`);
      throw error;
    }
  }

  /**
   * Pre-deployment checks
   */
  async preDeploymentChecks(serviceName) {
    console.log('\n' + '='.repeat(70));
    console.log('PRE-DEPLOYMENT SAFETY CHECKS');
    console.log('='.repeat(70) + '\n');

    const results = {
      drift: null,
      currentState: null,
      backup: null,
      versionLock: null,
      safetoDeployProceed: false
    };

    // Step 1: Get current state
    console.log('📊 Step 1: Getting current deployment state...');
    results.currentState = await this.manifestTracker.getCurrentState(serviceName);

    if (results.currentState) {
      console.log(`   ✅ Current version: ${results.currentState.version}`);
      console.log(`   📦 Current image: ${results.currentState.image?.fullRef}`);
      console.log(`   📅 Last deployed: ${results.currentState.timestamp}`);
    } else {
      console.log('   ℹ️  No previous deployment found (new service)');
    }

    // Step 2: Drift detection
    if (!this.skipDriftCheck) {
      console.log('\n🔍 Step 2: Checking for configuration drift...');

      try {
        results.drift = await this.driftDetector.detectServiceDrift(serviceName, this.clusterName);

        if (!results.drift.hasDrift) {
          console.log('   ✅ No drift detected');
        } else {
          console.log(`   ⚠️  Drift detected: ${results.drift.severity}`);
          console.log(`   📝 ${results.drift.message}`);

          for (const d of results.drift.drifts.slice(0, 3)) {
            console.log(`      - ${d.field}: ${d.message}`);
          }

          if (results.drift.drifts.length > 3) {
            console.log(`      ... and ${results.drift.drifts.length - 3} more`);
          }

          // Check severity and get approval
          if (results.drift.severity === 'CRITICAL') {
            console.log('\n   ⛔ CRITICAL drift detected!');
            console.log('   This deployment may overwrite important manual changes.');
            console.log('   Proceeding without review could cause production incidents.\n');

            const proceed = await this.askConfirmation('Do you want to proceed anyway?', false);

            if (!proceed) {
              throw new Error('Deployment cancelled due to CRITICAL drift');
            }
          } else if (results.drift.severity === 'HIGH') {
            console.log('\n   🔴 HIGH severity drift detected!');
            console.log('   Manual changes will be overwritten.\n');

            const proceed = await this.askConfirmation('Continue with deployment?', false);

            if (!proceed) {
              throw new Error('Deployment cancelled due to HIGH drift');
            }
          } else if (results.drift.severity === 'MEDIUM') {
            console.log('\n   🟡 MEDIUM severity drift detected.');

            const proceed = await this.askConfirmation('Continue with deployment?', true);

            if (!proceed) {
              throw new Error('Deployment cancelled due to MEDIUM drift');
            }
          }
        }
      } catch (error) {
        if (error.message.includes('cancelled')) {
          throw error;
        }
        console.log(`   ⚠️  Drift check failed: ${error.message}`);
        console.log('   Continuing without drift check...');
      }
    } else {
      console.log('\n⏭️  Step 2: Drift check skipped (--skip-drift-check)');
    }

    // Step 3: Create backup
    console.log('\n💾 Step 3: Creating backup...');

    if (results.currentState) {
      results.backup = await this.manifestTracker.createBackup(serviceName);
      console.log(`   ✅ Backup created: ${results.backup.backupId}`);
      console.log(`   📁 Location: ${results.backup.backupPath}`);
    } else {
      console.log('   ℹ️  No backup needed (first deployment)');
    }

    // Step 4: Final approval
    console.log('\n✅ Step 4: Pre-deployment checks complete\n');

    const summary = [
      `Service: ${serviceName}`,
      `Cluster: ${this.clusterName}`,
      results.drift ? `Drift: ${results.drift.severity || 'NONE'}` : 'Drift: UNCHECKED',
      results.backup ? `Backup: ${results.backup.backupId}` : 'Backup: NONE',
      this.dryRun ? 'Mode: DRY RUN' : 'Mode: LIVE DEPLOYMENT'
    ];

    console.log('   ' + summary.join('\n   '));

    console.log();
    const finalApproval = await this.askConfirmation('Proceed with deployment?', true);

    if (!finalApproval) {
      throw new Error('Deployment cancelled by user');
    }

    results.safeToProceed = true;
    return results;
  }

  /**
   * Deploy with safety checks
   */
  async deploy(serviceName, deploymentOptions) {
    const {
      imageName,
      imageTag,
      version,
      config = {},
      taskDefinitionArn,
      desiredCount,
      deployCommand
    } = deploymentOptions;

    console.log('\n' + '='.repeat(70));
    console.log(`🚀 SAFE DEPLOYMENT: ${serviceName}`);
    console.log('='.repeat(70));

    let preCheckResults = null;

    try {
      // Pre-deployment checks
      preCheckResults = await this.preDeploymentChecks(serviceName);

      // Lock version
      console.log('\n🔒 Step 5: Locking version...');
      await this.versionLock.lockService(serviceName, {
        imageName,
        imageTag,
        version,
        metadata: {
          deployedAt: new Date().toISOString(),
          deployedBy: process.env.USER
        }
      });
      console.log('   ✅ Version locked');

      // Execute deployment
      console.log('\n⚡ Step 6: Executing deployment...');

      if (deployCommand) {
        this.exec(deployCommand, 'Running deployment command');
      }

      // Create deployment manifest
      console.log('\n📝 Step 7: Creating deployment manifest...');

      const manifest = await this.manifestTracker.createManifest({
        serviceName,
        version,
        imageName,
        imageTag,
        environment: process.env.ENVIRONMENT || 'production',
        config,
        taskDefinitionArn,
        desiredCount,
        metadata: {
          drift: preCheckResults.drift,
          backup: preCheckResults.backup
        }
      });

      console.log(`   ✅ Manifest created: ${manifest.deploymentId}`);

      // Post-deployment verification
      console.log('\n🔍 Step 8: Post-deployment verification...');

      await this.sleep(5000); // Wait for deployment to propagate

      const postDrift = await this.driftDetector.detectServiceDrift(serviceName, this.clusterName);

      if (!postDrift.hasDrift) {
        console.log('   ✅ Deployment verified - no drift detected');
      } else {
        console.log(`   ⚠️  Post-deployment drift detected: ${postDrift.severity}`);
      }

      // Success!
      console.log('\n' + '='.repeat(70));
      console.log('✅ DEPLOYMENT SUCCESSFUL');
      console.log('='.repeat(70));
      console.log(`\nService: ${serviceName}`);
      console.log(`Version: ${version}`);
      console.log(`Deployment ID: ${manifest.deploymentId}`);
      console.log(`Image: ${imageName}:${imageTag}`);
      console.log(`\nTo rollback: aeims-ctl rollback ${serviceName} ${manifest.deploymentId}`);
      console.log();

      return {
        success: true,
        manifest,
        preCheckResults,
        postDrift
      };
    } catch (error) {
      console.error('\n' + '='.repeat(70));
      console.error('❌ DEPLOYMENT FAILED');
      console.error('='.repeat(70));
      console.error(`\nError: ${error.message}\n`);

      // Offer rollback if we have a backup
      if (preCheckResults?.backup && !this.dryRun) {
        console.log('A backup exists from before this deployment attempt.');
        const rollback = await this.askConfirmation('Would you like to rollback?', true);

        if (rollback) {
          console.log('\n🔙 Rolling back...');

          try {
            await this.manifestTracker.rollback(
              serviceName,
              preCheckResults.backup.state.deploymentId
            );
            console.log('✅ Rollback successful');
          } catch (rollbackError) {
            console.error(`❌ Rollback failed: ${rollbackError.message}`);
          }
        }
      }

      throw error;
    }
  }

  /**
   * Sleep helper
   */
  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}

// CLI interface
if (require.main === module) {
  const args = process.argv.slice(2);
  const flags = {
    autoApprove: args.includes('--auto-approve') || args.includes('-y'),
    skipDriftCheck: args.includes('--skip-drift-check'),
    dryRun: args.includes('--dry-run'),
    clusterName: args.find(arg => arg.startsWith('--cluster='))?.split('=')[1] || 'aeims-cluster-production'
  };

  const serviceName = args.find(arg => !arg.startsWith('--'));

  if (!serviceName) {
    console.log(`
Usage: safe-deploy.js <service-name> [flags]

Flags:
  --auto-approve, -y      Skip all confirmation prompts
  --skip-drift-check      Skip drift detection (not recommended)
  --dry-run               Show what would happen without executing
  --cluster=<name>        Specify ECS cluster name

Examples:
  # Deploy with safety checks
  safe-deploy.js admin-service

  # Deploy with auto-approval (CI/CD)
  safe-deploy.js admin-service --auto-approve

  # Dry run to see what would happen
  safe-deploy.js admin-service --dry-run

Note: This is a wrapper script. For actual deployment, integrate this into
your existing deployment scripts (deploy.sh, deploy-unified.sh, etc.)
    `);
    process.exit(1);
  }

  const safeDeploy = new SafeDeploy(flags);

  (async () => {
    // Example: You would pass actual deployment options here
    await safeDeploy.deploy(serviceName, {
      imageName: '515966511618.dkr.ecr.us-east-1.amazonaws.com/' + serviceName,
      imageTag: 'latest',
      version: '1.0.0',
      config: {},
      desiredCount: 2,
      deployCommand: `echo "Would deploy ${serviceName} here"`
    });
  })().catch(err => {
    console.error(`\nFatal error: ${err.message}`);
    process.exit(1);
  });
}

module.exports = SafeDeploy;
