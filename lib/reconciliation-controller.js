#!/usr/bin/env node

/**
 * Reconciliation Controller
 *
 * Reconciles desired state with actual state by detecting drift and
 * safely applying corrections. Supports dry-run mode and approval gates.
 */

const { execSync } = require('child_process');
const readline = require('readline');
const ManifestTracker = require('./manifest-tracker');
const DriftDetector = require('./drift-detector');

class ReconciliationController {
  constructor(options = {}) {
    this.manifestTracker = new ManifestTracker();
    this.driftDetector = new DriftDetector();
    this.dryRun = options.dryRun || false;
    this.autoApprove = options.autoApprove || false;
    this.region = process.env.AWS_REGION || 'us-east-1';
  }

  /**
   * Execute command with logging
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
   * Ask for user confirmation
   */
  async askConfirmation(message) {
    if (this.autoApprove || this.dryRun) {
      return true;
    }

    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout
    });

    return new Promise((resolve) => {
      rl.question(`${message} (yes/no): `, (answer) => {
        rl.close();
        resolve(answer.toLowerCase() === 'yes' || answer.toLowerCase() === 'y');
      });
    });
  }

  /**
   * Reconcile a single service
   */
  async reconcileService(serviceName, clusterName = 'aeims-cluster-production') {
    console.log(`\n${'='.repeat(70)}`);
    console.log(`🔄 Reconciling: ${serviceName}`);
    console.log(`${'='.repeat(70)}\n`);

    // Step 1: Detect drift
    console.log('📊 Step 1: Detecting drift...');
    const drift = await this.driftDetector.detectServiceDrift(serviceName, clusterName);

    if (!drift.hasDrift) {
      console.log('✅ No drift detected - service is in sync\n');
      return {
        serviceName,
        action: 'NONE',
        reason: 'No drift detected',
        drift
      };
    }

    console.log(`⚠️  Drift detected: ${drift.message}`);
    console.log(`   Severity: ${drift.severity}`);

    // Step 2: Display drift details
    console.log('\n📝 Step 2: Drift details:');
    for (const d of drift.drifts) {
      console.log(`   - ${d.field}: ${d.message}`);
      if (d.details && d.details.length > 0) {
        for (const detail of d.details.slice(0, 3)) {
          console.log(`     • ${detail.key}: ${JSON.stringify(detail.manifest)} → ${JSON.stringify(detail.aws)}`);
        }
        if (d.details.length > 3) {
          console.log(`     ... and ${d.details.length - 3} more changes`);
        }
      }
    }

    // Step 3: Check severity and get approval
    if (drift.severity === 'CRITICAL') {
      console.log('\n⛔ CRITICAL drift detected - manual intervention required');
      console.log('   This deployment would be UNSAFE without review.\n');

      const proceed = await this.askConfirmation('Do you want to proceed anyway?');
      if (!proceed) {
        console.log('❌ Reconciliation cancelled by user\n');
        return {
          serviceName,
          action: 'CANCELLED',
          reason: 'Critical drift - user cancelled',
          drift
        };
      }
    } else if (drift.severity === 'HIGH') {
      console.log('\n🔴 HIGH severity drift - review recommended');

      const proceed = await this.askConfirmation('Do you want to proceed with reconciliation?');
      if (!proceed) {
        console.log('❌ Reconciliation cancelled by user\n');
        return {
          serviceName,
          action: 'CANCELLED',
          reason: 'High drift - user cancelled',
          drift
        };
      }
    }

    // Step 4: Create backup
    console.log('\n💾 Step 3: Creating backup...');
    const backup = await this.manifestTracker.createBackup(serviceName);
    if (backup) {
      console.log(`   ✅ Backup created: ${backup.backupId}`);
    }

    // Step 5: Plan reconciliation actions
    console.log('\n📋 Step 4: Planning reconciliation actions...');
    const actions = this.planReconciliationActions(drift);

    for (const action of actions) {
      console.log(`   - ${action.description}`);
    }

    // Step 6: Get final approval
    const finalApproval = await this.askConfirmation('\nProceed with these changes?');
    if (!finalApproval && !this.dryRun) {
      console.log('❌ Reconciliation cancelled by user\n');
      return {
        serviceName,
        action: 'CANCELLED',
        reason: 'User cancelled before execution',
        drift,
        backup
      };
    }

    // Step 7: Execute reconciliation
    console.log('\n⚡ Step 5: Executing reconciliation...');

    const results = [];
    for (const action of actions) {
      try {
        const result = await this.executeAction(action, serviceName, clusterName);
        results.push({
          action: action.type,
          success: true,
          result
        });
      } catch (error) {
        console.error(`   ❌ Action failed: ${error.message}`);
        results.push({
          action: action.type,
          success: false,
          error: error.message
        });

        // If any action fails, stop and offer rollback
        console.log('\n⚠️  Reconciliation failed. Would you like to rollback?');
        const rollback = await this.askConfirmation('Rollback to previous state?');

        if (rollback && backup) {
          await this.rollbackService(serviceName, backup.state.deploymentId);
        }

        return {
          serviceName,
          action: 'FAILED',
          reason: `Action ${action.type} failed: ${error.message}`,
          drift,
          backup,
          results
        };
      }
    }

    // Step 8: Verify reconciliation
    console.log('\n🔍 Step 6: Verifying reconciliation...');
    const postDrift = await this.driftDetector.detectServiceDrift(serviceName, clusterName);

    if (!postDrift.hasDrift) {
      console.log('✅ Reconciliation successful - no drift detected\n');
    } else {
      console.log(`⚠️  Some drift still exists: ${postDrift.drifts.length} remaining\n`);
    }

    return {
      serviceName,
      action: 'RECONCILED',
      reason: 'Successfully reconciled',
      drift,
      postDrift,
      backup,
      results
    };
  }

  /**
   * Plan reconciliation actions based on detected drift
   */
  planReconciliationActions(drift) {
    const actions = [];

    for (const d of drift.drifts) {
      switch (d.field) {
        case 'desiredCount':
          actions.push({
            type: 'UPDATE_DESIRED_COUNT',
            description: `Update desired count from ${d.aws} to ${d.manifest}`,
            data: {
              desiredCount: d.manifest
            }
          });
          break;

        case 'image':
          actions.push({
            type: 'UPDATE_IMAGE',
            description: `Update image from ${d.aws} to ${d.manifest}`,
            data: {
              image: d.manifest
            }
          });
          break;

        case 'environment':
          actions.push({
            type: 'UPDATE_ENVIRONMENT',
            description: `Update environment variables (${d.details.length} changes)`,
            data: {
              environment: drift.manifestState.config.data.environment,
              changes: d.details
            }
          });
          break;

        default:
          actions.push({
            type: 'UPDATE_TASK_DEFINITION',
            description: `Update task definition for field: ${d.field}`,
            data: d
          });
      }
    }

    return actions;
  }

  /**
   * Execute a reconciliation action
   */
  async executeAction(action, serviceName, clusterName) {
    switch (action.type) {
      case 'UPDATE_DESIRED_COUNT':
        return this.updateDesiredCount(serviceName, clusterName, action.data.desiredCount);

      case 'UPDATE_IMAGE':
      case 'UPDATE_ENVIRONMENT':
      case 'UPDATE_TASK_DEFINITION':
        return this.updateTaskDefinition(serviceName, clusterName, action);

      default:
        throw new Error(`Unknown action type: ${action.type}`);
    }
  }

  /**
   * Update ECS service desired count
   */
  updateDesiredCount(serviceName, clusterName, desiredCount) {
    const command = `aws ecs update-service --cluster ${clusterName} --service ${serviceName} --desired-count ${desiredCount} --region ${this.region}`;

    this.exec(command, `Updating desired count to ${desiredCount}`);

    return { desiredCount };
  }

  /**
   * Update ECS task definition and service
   */
  async updateTaskDefinition(serviceName, clusterName, action) {
    // Get current task definition
    const currentState = await this.driftDetector.getECSServiceState(clusterName, serviceName);

    if (!currentState) {
      throw new Error('Could not get current task definition');
    }

    // Get manifest state
    const manifestState = await this.manifestTracker.getCurrentState(serviceName);

    if (!manifestState) {
      throw new Error('No manifest state found');
    }

    // Register new task definition with updated values
    const taskDefFamily = currentState.taskDefinition.split('/')[1].split(':')[0];

    // This is a simplified version - in production, you'd need to construct
    // the full task definition JSON and register it
    const command = `aws ecs update-service --cluster ${clusterName} --service ${serviceName} --task-definition ${manifestState.aws.taskDefinitionArn} --region ${this.region}`;

    this.exec(command, `Updating task definition for ${serviceName}`);

    return {
      taskDefinition: manifestState.aws.taskDefinitionArn
    };
  }

  /**
   * Rollback service to a previous deployment
   */
  async rollbackService(serviceName, deploymentId) {
    console.log(`\n🔙 Rolling back ${serviceName} to ${deploymentId}...`);

    const targetState = await this.manifestTracker.rollback(serviceName, deploymentId);

    console.log(`   ✅ Manifest rolled back to ${targetState.timestamp}`);

    // Now reconcile to apply the rollback
    return this.reconcileService(serviceName);
  }

  /**
   * Reconcile all services
   */
  async reconcileAll(clusterName = 'aeims-cluster-production') {
    const services = await this.manifestTracker.getAllServices();

    console.log(`\n🔄 Reconciling ${services.length} services...\n`);

    const results = [];

    for (const serviceName of services) {
      const result = await this.reconcileService(serviceName, clusterName);
      results.push(result);

      // Pause between services to avoid rate limiting
      await new Promise(resolve => setTimeout(resolve, 2000));
    }

    return {
      timestamp: new Date().toISOString(),
      totalServices: results.length,
      reconciled: results.filter(r => r.action === 'RECONCILED').length,
      cancelled: results.filter(r => r.action === 'CANCELLED').length,
      failed: results.filter(r => r.action === 'FAILED').length,
      noAction: results.filter(r => r.action === 'NONE').length,
      results
    };
  }

  /**
   * Generate reconciliation report
   */
  generateReport(reconcileResults) {
    let report = '\n=== RECONCILIATION REPORT ===\n\n';
    report += `Timestamp: ${reconcileResults.timestamp}\n`;
    report += `Total Services: ${reconcileResults.totalServices}\n`;
    report += `✅ Reconciled: ${reconcileResults.reconciled}\n`;
    report += `⏭️  No Action Needed: ${reconcileResults.noAction}\n`;
    report += `❌ Cancelled: ${reconcileResults.cancelled}\n`;
    report += `⚠️  Failed: ${reconcileResults.failed}\n\n`;

    for (const result of reconcileResults.results) {
      const icon = {
        'RECONCILED': '✅',
        'NONE': '⏭️',
        'CANCELLED': '❌',
        'FAILED': '⚠️'
      }[result.action] || '❓';

      report += `${icon} ${result.serviceName}: ${result.reason}\n`;
    }

    return report;
  }
}

// CLI interface
if (require.main === module) {
  const args = process.argv.slice(2);
  const flags = {
    dryRun: args.includes('--dry-run'),
    autoApprove: args.includes('--auto-approve')
  };

  const controller = new ReconciliationController(flags);

  const command = args.find(arg => !arg.startsWith('--'));
  const commandArgs = args.filter(arg => !arg.startsWith('--') && arg !== command);

  (async () => {
    await controller.manifestTracker.initialize();

    switch (command) {
      case 'service':
        const serviceName = commandArgs[0];
        const cluster = commandArgs[1] || 'aeims-cluster-production';
        await controller.reconcileService(serviceName, cluster);
        break;

      case 'all':
        const allCluster = commandArgs[0] || 'aeims-cluster-production';
        const results = await controller.reconcileAll(allCluster);
        console.log(controller.generateReport(results));
        break;

      case 'rollback':
        const rollbackService = commandArgs[0];
        const deploymentId = commandArgs[1];
        if (!deploymentId) {
          console.error('Error: deploymentId required for rollback');
          process.exit(1);
        }
        await controller.rollbackService(rollbackService, deploymentId);
        break;

      default:
        console.log(`
Usage: reconciliation-controller.js <command> [args] [flags]

Commands:
  service <name> [cluster]           Reconcile a specific service
  all [cluster]                      Reconcile all services
  rollback <service> <deploymentId>  Rollback to a previous deployment

Flags:
  --dry-run                          Show what would be done without executing
  --auto-approve                     Skip confirmation prompts

Examples:
  # Reconcile a single service with review
  reconciliation-controller.js service admin-service

  # Dry run to see what would happen
  reconciliation-controller.js service admin-service --dry-run

  # Reconcile all services automatically
  reconciliation-controller.js all --auto-approve

  # Rollback a service
  reconciliation-controller.js rollback admin-service admin-service-1699876543210
        `);
        process.exit(1);
    }
  })().catch(err => {
    console.error('Error:', err.message);
    if (err.stack) {
      console.error(err.stack);
    }
    process.exit(1);
  });
}

module.exports = ReconciliationController;
