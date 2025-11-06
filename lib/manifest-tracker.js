#!/usr/bin/env node

/**
 * Deployment Manifest Tracker
 *
 * Tracks all deployments with full state, config hashes, and version information.
 * Enables drift detection, rollback, and reconciliation capabilities.
 */

const fs = require('fs').promises;
const path = require('path');
const crypto = require('crypto');
const { execSync } = require('child_process');

const MANIFEST_DIR = path.join(__dirname, '../.aeims/manifests');
const STATE_DIR = path.join(__dirname, '../.aeims/state');
const BACKUP_DIR = path.join(__dirname, '../.aeims/backups');

class ManifestTracker {
  constructor() {
    this.manifestDir = MANIFEST_DIR;
    this.stateDir = STATE_DIR;
    this.backupDir = BACKUP_DIR;
  }

  /**
   * Initialize manifest tracking
   */
  async initialize() {
    await fs.mkdir(this.manifestDir, { recursive: true });
    await fs.mkdir(this.stateDir, { recursive: true });
    await fs.mkdir(this.backupDir, { recursive: true });
  }

  /**
   * Generate SHA256 hash of a configuration object
   */
  hashConfig(config) {
    const normalized = JSON.stringify(config, Object.keys(config).sort());
    return crypto.createHash('sha256').update(normalized).digest('hex');
  }

  /**
   * Get current Git commit hash
   */
  getGitCommit() {
    try {
      return execSync('git rev-parse HEAD', { encoding: 'utf8' }).trim();
    } catch (error) {
      return 'unknown';
    }
  }

  /**
   * Get current Git branch
   */
  getGitBranch() {
    try {
      return execSync('git rev-parse --abbrev-ref HEAD', { encoding: 'utf8' }).trim();
    } catch (error) {
      return 'unknown';
    }
  }

  /**
   * Get Docker image digest (SHA256)
   */
  async getImageDigest(imageName) {
    try {
      const digest = execSync(`docker inspect --format='{{index .RepoDigests 0}}' ${imageName}`, { encoding: 'utf8' }).trim();
      return digest || null;
    } catch (error) {
      // If image not found locally, try to get from ECR
      try {
        const [repo, tag] = imageName.split(':');
        const ecrDigest = execSync(
          `aws ecr describe-images --repository-name ${repo} --image-ids imageTag=${tag || 'latest'} --query 'imageDetails[0].imageDigest' --output text`,
          { encoding: 'utf8' }
        ).trim();
        return ecrDigest !== 'None' ? ecrDigest : null;
      } catch (ecrError) {
        return null;
      }
    }
  }

  /**
   * Create a deployment manifest
   */
  async createManifest(options) {
    const {
      serviceName,
      version,
      imageName,
      imageTag,
      environment,
      config,
      taskDefinitionArn,
      desiredCount,
      metadata = {}
    } = options;

    const timestamp = new Date().toISOString();
    const deploymentId = `${serviceName}-${Date.now()}`;

    const manifest = {
      deploymentId,
      serviceName,
      version,
      timestamp,
      environment,
      git: {
        commit: this.getGitCommit(),
        branch: this.getGitBranch()
      },
      image: {
        name: imageName,
        tag: imageTag,
        digest: await this.getImageDigest(imageName + ':' + imageTag),
        fullRef: `${imageName}:${imageTag}`
      },
      config: {
        hash: this.hashConfig(config),
        data: config
      },
      aws: {
        taskDefinitionArn,
        desiredCount,
        region: process.env.AWS_REGION || 'us-east-1'
      },
      metadata: {
        deployer: process.env.USER || 'unknown',
        hostname: require('os').hostname(),
        ...metadata
      }
    };

    // Save manifest
    const manifestPath = path.join(this.manifestDir, `${deploymentId}.json`);
    await fs.writeFile(manifestPath, JSON.stringify(manifest, null, 2));

    // Update current state pointer
    const currentStatePath = path.join(this.stateDir, `${serviceName}.current.json`);
    await fs.writeFile(currentStatePath, JSON.stringify(manifest, null, 2));

    // Add to deployment history
    await this.addToHistory(serviceName, manifest);

    return manifest;
  }

  /**
   * Add deployment to service history
   */
  async addToHistory(serviceName, manifest) {
    const historyPath = path.join(this.stateDir, `${serviceName}.history.json`);

    let history = [];
    try {
      const existingHistory = await fs.readFile(historyPath, 'utf8');
      history = JSON.parse(existingHistory);
    } catch (error) {
      // File doesn't exist yet
    }

    history.unshift(manifest);

    // Keep last 50 deployments
    if (history.length > 50) {
      history = history.slice(0, 50);
    }

    await fs.writeFile(historyPath, JSON.stringify(history, null, 2));
  }

  /**
   * Get current deployed state for a service
   */
  async getCurrentState(serviceName) {
    const currentStatePath = path.join(this.stateDir, `${serviceName}.current.json`);

    try {
      const state = await fs.readFile(currentStatePath, 'utf8');
      return JSON.parse(state);
    } catch (error) {
      return null;
    }
  }

  /**
   * Get deployment history for a service
   */
  async getHistory(serviceName, limit = 10) {
    const historyPath = path.join(this.stateDir, `${serviceName}.history.json`);

    try {
      const history = await fs.readFile(historyPath, 'utf8');
      const allHistory = JSON.parse(history);
      return allHistory.slice(0, limit);
    } catch (error) {
      return [];
    }
  }

  /**
   * Detect drift between desired and actual state
   */
  async detectDrift(serviceName, desiredState) {
    const currentState = await this.getCurrentState(serviceName);

    if (!currentState) {
      return {
        hasDrift: true,
        reason: 'NO_CURRENT_STATE',
        message: 'Service has never been deployed via manifest tracker',
        drifts: []
      };
    }

    const drifts = [];

    // Check image drift
    if (desiredState.image && currentState.image) {
      if (desiredState.image.digest && currentState.image.digest) {
        if (desiredState.image.digest !== currentState.image.digest) {
          drifts.push({
            field: 'image.digest',
            current: currentState.image.digest,
            desired: desiredState.image.digest,
            severity: 'HIGH'
          });
        }
      } else if (desiredState.image.tag !== currentState.image.tag) {
        drifts.push({
          field: 'image.tag',
          current: currentState.image.tag,
          desired: desiredState.image.tag,
          severity: 'MEDIUM'
        });
      }
    }

    // Check config drift
    if (desiredState.config && currentState.config) {
      const desiredHash = typeof desiredState.config.hash === 'string'
        ? desiredState.config.hash
        : this.hashConfig(desiredState.config.data || desiredState.config);

      if (desiredHash !== currentState.config.hash) {
        drifts.push({
          field: 'config',
          current: currentState.config.hash,
          desired: desiredHash,
          severity: 'HIGH',
          details: this.diffConfig(currentState.config.data, desiredState.config.data || desiredState.config)
        });
      }
    }

    // Check desired count drift
    if (desiredState.aws?.desiredCount !== undefined &&
        currentState.aws?.desiredCount !== desiredState.aws.desiredCount) {
      drifts.push({
        field: 'aws.desiredCount',
        current: currentState.aws.desiredCount,
        desired: desiredState.aws.desiredCount,
        severity: 'MEDIUM'
      });
    }

    return {
      hasDrift: drifts.length > 0,
      reason: drifts.length > 0 ? 'CONFIGURATION_DRIFT' : 'NO_DRIFT',
      message: drifts.length > 0
        ? `Found ${drifts.length} configuration drift(s)`
        : 'No drift detected',
      drifts,
      currentState,
      desiredState
    };
  }

  /**
   * Diff two configuration objects
   */
  diffConfig(current, desired) {
    const diffs = [];
    const allKeys = new Set([
      ...Object.keys(current || {}),
      ...Object.keys(desired || {})
    ]);

    for (const key of allKeys) {
      const currentVal = current?.[key];
      const desiredVal = desired?.[key];

      if (JSON.stringify(currentVal) !== JSON.stringify(desiredVal)) {
        diffs.push({
          key,
          current: currentVal,
          desired: desiredVal
        });
      }
    }

    return diffs;
  }

  /**
   * Create a backup before deployment
   */
  async createBackup(serviceName) {
    const currentState = await this.getCurrentState(serviceName);

    if (!currentState) {
      return null;
    }

    const backupId = `${serviceName}-${Date.now()}.backup.json`;
    const backupPath = path.join(this.backupDir, backupId);

    await fs.writeFile(backupPath, JSON.stringify(currentState, null, 2));

    return {
      backupId,
      backupPath,
      state: currentState
    };
  }

  /**
   * List all backups for a service
   */
  async listBackups(serviceName) {
    const files = await fs.readdir(this.backupDir);
    const serviceBackups = files.filter(f => f.startsWith(`${serviceName}-`) && f.endsWith('.backup.json'));

    const backups = [];
    for (const file of serviceBackups) {
      const backupPath = path.join(this.backupDir, file);
      const stats = await fs.stat(backupPath);
      const content = await fs.readFile(backupPath, 'utf8');
      const state = JSON.parse(content);

      backups.push({
        backupId: file,
        backupPath,
        timestamp: stats.mtime,
        state
      });
    }

    return backups.sort((a, b) => b.timestamp - a.timestamp);
  }

  /**
   * Rollback to a previous deployment
   */
  async rollback(serviceName, deploymentId) {
    const history = await this.getHistory(serviceName, 50);
    const targetDeployment = history.find(d => d.deploymentId === deploymentId);

    if (!targetDeployment) {
      throw new Error(`Deployment ${deploymentId} not found in history`);
    }

    // Create backup of current state
    await this.createBackup(serviceName);

    // Restore target deployment as current
    const currentStatePath = path.join(this.stateDir, `${serviceName}.current.json`);
    await fs.writeFile(currentStatePath, JSON.stringify(targetDeployment, null, 2));

    return targetDeployment;
  }

  /**
   * Get all services with manifests
   */
  async getAllServices() {
    const files = await fs.readdir(this.stateDir);
    const services = new Set();

    for (const file of files) {
      if (file.endsWith('.current.json')) {
        const serviceName = file.replace('.current.json', '');
        services.add(serviceName);
      }
    }

    return Array.from(services);
  }

  /**
   * Get summary of all deployments
   */
  async getSummary() {
    const services = await this.getAllServices();
    const summary = [];

    for (const serviceName of services) {
      const currentState = await this.getCurrentState(serviceName);
      const history = await this.getHistory(serviceName, 5);

      summary.push({
        serviceName,
        currentDeployment: currentState,
        recentDeployments: history.length,
        lastDeployed: currentState?.timestamp
      });
    }

    return summary;
  }
}

// CLI interface
if (require.main === module) {
  const tracker = new ManifestTracker();

  const command = process.argv[2];
  const args = process.argv.slice(3);

  (async () => {
    await tracker.initialize();

    switch (command) {
      case 'init':
        console.log('✅ Manifest tracker initialized');
        break;

      case 'summary':
        const summary = await tracker.getSummary();
        console.log(JSON.stringify(summary, null, 2));
        break;

      case 'current':
        const serviceName = args[0];
        const current = await tracker.getCurrentState(serviceName);
        console.log(JSON.stringify(current, null, 2));
        break;

      case 'history':
        const historyService = args[0];
        const limit = parseInt(args[1]) || 10;
        const history = await tracker.getHistory(historyService, limit);
        console.log(JSON.stringify(history, null, 2));
        break;

      case 'backups':
        const backupService = args[0];
        const backups = await tracker.listBackups(backupService);
        console.log(JSON.stringify(backups, null, 2));
        break;

      default:
        console.log(`
Usage: manifest-tracker.js <command> [args]

Commands:
  init                          Initialize manifest tracking
  summary                       Get summary of all deployments
  current <service>             Get current state of a service
  history <service> [limit]     Get deployment history (default: 10)
  backups <service>             List all backups for a service
        `);
    }
  })().catch(err => {
    console.error('Error:', err.message);
    process.exit(1);
  });
}

module.exports = ManifestTracker;
