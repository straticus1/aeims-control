#!/usr/bin/env node

/**
 * Drift Detector
 *
 * Detects configuration drift between desired state (IaC) and actual state (AWS).
 * Integrates with AWS ECS, EC2, and other services to detect manual changes.
 */

const { execSync } = require('child_process');
const ManifestTracker = require('./manifest-tracker');

class DriftDetector {
  constructor() {
    this.manifestTracker = new ManifestTracker();
    this.region = process.env.AWS_REGION || 'us-east-1';
  }

  /**
   * Execute AWS CLI command and return JSON result
   */
  awsCommand(command) {
    try {
      const result = execSync(command, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
      return JSON.parse(result);
    } catch (error) {
      throw new Error(`AWS command failed: ${error.message}`);
    }
  }

  /**
   * Get ECS service details from AWS
   */
  async getECSServiceState(clusterName, serviceName) {
    try {
      const result = this.awsCommand(
        `aws ecs describe-services --cluster ${clusterName} --services ${serviceName} --region ${this.region}`
      );

      if (!result.services || result.services.length === 0) {
        return null;
      }

      const service = result.services[0];

      // Get task definition details
      const taskDef = this.awsCommand(
        `aws ecs describe-task-definition --task-definition ${service.taskDefinition} --region ${this.region}`
      );

      return {
        serviceName: service.serviceName,
        status: service.status,
        desiredCount: service.desiredCount,
        runningCount: service.runningCount,
        pendingCount: service.pendingCount,
        taskDefinition: service.taskDefinition,
        taskDefinitionArn: service.taskDefinition,
        containerDefinitions: taskDef.taskDefinition.containerDefinitions,
        environment: this.extractEnvironment(taskDef.taskDefinition.containerDefinitions),
        image: this.extractImage(taskDef.taskDefinition.containerDefinitions),
        launchType: service.launchType,
        networkConfiguration: service.networkConfiguration,
        loadBalancers: service.loadBalancers
      };
    } catch (error) {
      console.error(`Failed to get ECS service state: ${error.message}`);
      return null;
    }
  }

  /**
   * Extract environment variables from container definitions
   */
  extractEnvironment(containerDefinitions) {
    const env = {};

    for (const container of containerDefinitions) {
      if (container.environment) {
        for (const { name, value } of container.environment) {
          env[name] = value;
        }
      }
    }

    return env;
  }

  /**
   * Extract image information from container definitions
   */
  extractImage(containerDefinitions) {
    if (containerDefinitions.length === 0) return null;

    const primaryContainer = containerDefinitions[0];
    const imageRef = primaryContainer.image;

    // Parse image reference
    const [imageName, tag] = imageRef.split(':');

    return {
      fullRef: imageRef,
      name: imageName,
      tag: tag || 'latest'
    };
  }

  /**
   * Detect drift for a specific ECS service
   */
  async detectServiceDrift(serviceName, clusterName = 'aeims-cluster-production') {
    // Get current manifest state
    const manifestState = await this.manifestTracker.getCurrentState(serviceName);

    // Get actual AWS state
    const awsState = await this.getECSServiceState(clusterName, serviceName);

    if (!awsState) {
      return {
        serviceName,
        hasDrift: true,
        severity: 'CRITICAL',
        reason: 'SERVICE_NOT_FOUND',
        message: 'Service not found in AWS ECS',
        drifts: []
      };
    }

    if (!manifestState) {
      return {
        serviceName,
        hasDrift: true,
        severity: 'HIGH',
        reason: 'NO_MANIFEST',
        message: 'Service exists in AWS but has no manifest (deployed outside control plane)',
        awsState,
        drifts: []
      };
    }

    // Compare states
    const drifts = [];

    // Check desired count
    if (awsState.desiredCount !== manifestState.aws?.desiredCount) {
      drifts.push({
        field: 'desiredCount',
        manifest: manifestState.aws?.desiredCount,
        aws: awsState.desiredCount,
        severity: 'MEDIUM',
        message: `Desired count changed manually: ${manifestState.aws?.desiredCount} → ${awsState.desiredCount}`
      });
    }

    // Check image
    if (manifestState.image && awsState.image) {
      if (manifestState.image.fullRef !== awsState.image.fullRef) {
        drifts.push({
          field: 'image',
          manifest: manifestState.image.fullRef,
          aws: awsState.image.fullRef,
          severity: 'HIGH',
          message: `Image changed: ${manifestState.image.fullRef} → ${awsState.image.fullRef}`
        });
      }
    }

    // Check environment variables
    const manifestEnv = manifestState.config?.data?.environment || {};
    const awsEnv = awsState.environment || {};

    const envDrifts = this.compareEnvironments(manifestEnv, awsEnv);
    if (envDrifts.length > 0) {
      drifts.push({
        field: 'environment',
        manifest: manifestEnv,
        aws: awsEnv,
        severity: 'HIGH',
        message: `Environment variables changed: ${envDrifts.length} drift(s)`,
        details: envDrifts
      });
    }

    const severity = this.calculateSeverity(drifts);

    return {
      serviceName,
      hasDrift: drifts.length > 0,
      severity,
      reason: drifts.length > 0 ? 'CONFIGURATION_DRIFT' : 'NO_DRIFT',
      message: drifts.length > 0
        ? `Detected ${drifts.length} configuration drift(s)`
        : 'No drift detected',
      drifts,
      manifestState,
      awsState,
      timestamp: new Date().toISOString()
    };
  }

  /**
   * Compare environment variables
   */
  compareEnvironments(manifest, aws) {
    const drifts = [];
    const allKeys = new Set([...Object.keys(manifest), ...Object.keys(aws)]);

    for (const key of allKeys) {
      if (manifest[key] !== aws[key]) {
        drifts.push({
          key,
          manifest: manifest[key],
          aws: aws[key],
          type: !manifest[key] ? 'ADDED' : !aws[key] ? 'REMOVED' : 'CHANGED'
        });
      }
    }

    return drifts;
  }

  /**
   * Calculate overall severity from individual drifts
   */
  calculateSeverity(drifts) {
    if (drifts.length === 0) return 'NONE';

    const severities = drifts.map(d => d.severity);

    if (severities.includes('CRITICAL')) return 'CRITICAL';
    if (severities.includes('HIGH')) return 'HIGH';
    if (severities.includes('MEDIUM')) return 'MEDIUM';
    return 'LOW';
  }

  /**
   * Detect drift for all services
   */
  async detectAllDrift(clusterName = 'aeims-cluster-production') {
    const services = await this.manifestTracker.getAllServices();
    const results = [];

    for (const serviceName of services) {
      const drift = await this.detectServiceDrift(serviceName, clusterName);
      results.push(drift);
    }

    return {
      timestamp: new Date().toISOString(),
      clusterName,
      totalServices: results.length,
      servicesWithDrift: results.filter(r => r.hasDrift).length,
      criticalDrifts: results.filter(r => r.severity === 'CRITICAL').length,
      highDrifts: results.filter(r => r.severity === 'HIGH').length,
      mediumDrifts: results.filter(r => r.severity === 'MEDIUM').length,
      services: results
    };
  }

  /**
   * Generate drift report
   */
  generateReport(driftResults) {
    let report = '\n=== DRIFT DETECTION REPORT ===\n\n';
    report += `Timestamp: ${driftResults.timestamp}\n`;
    report += `Cluster: ${driftResults.clusterName}\n`;
    report += `Total Services: ${driftResults.totalServices}\n`;
    report += `Services with Drift: ${driftResults.servicesWithDrift}\n\n`;

    if (driftResults.criticalDrifts > 0) {
      report += `⛔ CRITICAL: ${driftResults.criticalDrifts}\n`;
    }
    if (driftResults.highDrifts > 0) {
      report += `🔴 HIGH: ${driftResults.highDrifts}\n`;
    }
    if (driftResults.mediumDrifts > 0) {
      report += `🟡 MEDIUM: ${driftResults.mediumDrifts}\n`;
    }

    report += '\n';

    for (const service of driftResults.services) {
      if (service.hasDrift) {
        report += `\n📦 ${service.serviceName} [${service.severity}]\n`;
        report += `   ${service.message}\n`;

        for (const drift of service.drifts) {
          report += `   - ${drift.field}: ${drift.message}\n`;
          if (drift.details && drift.details.length > 0) {
            for (const detail of drift.details.slice(0, 5)) {
              report += `     • ${detail.key}: ${detail.manifest} → ${detail.aws} (${detail.type})\n`;
            }
            if (drift.details.length > 5) {
              report += `     ... and ${drift.details.length - 5} more\n`;
            }
          }
        }
      }
    }

    return report;
  }

  /**
   * Check if deployment is safe (no critical drifts)
   */
  async isSafeToDeplo(serviceName, clusterName = 'aeims-cluster-production') {
    const drift = await this.detectServiceDrift(serviceName, clusterName);

    return {
      safe: drift.severity !== 'CRITICAL' && drift.severity !== 'HIGH',
      drift,
      recommendation: this.getRecommendation(drift)
    };
  }

  /**
   * Get deployment recommendation based on drift
   */
  getRecommendation(drift) {
    if (!drift.hasDrift) {
      return 'SAFE: No drift detected, safe to deploy';
    }

    switch (drift.severity) {
      case 'CRITICAL':
        return 'STOP: Critical drift detected, manual intervention required';
      case 'HIGH':
        return 'CAUTION: High severity drift, review changes before deploying';
      case 'MEDIUM':
        return 'REVIEW: Medium severity drift, review recommended';
      case 'LOW':
        return 'PROCEED: Low severity drift, safe to deploy with awareness';
      default:
        return 'UNKNOWN: Unable to determine safety';
    }
  }
}

// CLI interface
if (require.main === module) {
  const detector = new DriftDetector();

  const command = process.argv[2];
  const args = process.argv.slice(3);

  (async () => {
    switch (command) {
      case 'service':
        const serviceName = args[0];
        const cluster = args[1] || 'aeims-cluster-production';
        const drift = await detector.detectServiceDrift(serviceName, cluster);
        console.log(JSON.stringify(drift, null, 2));
        break;

      case 'all':
        const allCluster = args[0] || 'aeims-cluster-production';
        const allDrift = await detector.detectAllDrift(allCluster);
        console.log(JSON.stringify(allDrift, null, 2));
        break;

      case 'report':
        const reportCluster = args[0] || 'aeims-cluster-production';
        const results = await detector.detectAllDrift(reportCluster);
        console.log(detector.generateReport(results));
        break;

      case 'safe':
        const checkService = args[0];
        const checkCluster = args[1] || 'aeims-cluster-production';
        const safety = await detector.isSafeToDeplo(checkService, checkCluster);
        console.log(JSON.stringify(safety, null, 2));
        if (!safety.safe) {
          process.exit(1);
        }
        break;

      default:
        console.log(`
Usage: drift-detector.js <command> [args]

Commands:
  service <name> [cluster]    Detect drift for a specific service
  all [cluster]               Detect drift for all services
  report [cluster]            Generate human-readable drift report
  safe <name> [cluster]       Check if it's safe to deploy (exits 1 if not)
        `);
        process.exit(1);
    }
  })().catch(err => {
    console.error('Error:', err.message);
    process.exit(1);
  });
}

module.exports = DriftDetector;
