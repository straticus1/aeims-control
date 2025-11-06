#!/usr/bin/env node

/**
 * Version Lock Manager
 *
 * Manages version locking across multiple repositories and services.
 * Ensures all services use pinned versions with SHA256 digests.
 */

const fs = require('fs').promises;
const path = require('path');
const { execSync } = require('child_process');
const crypto = require('crypto');

const LOCK_FILE = path.join(__dirname, '../.aeims/version-lock.json');

class VersionLockManager {
  constructor() {
    this.lockFile = LOCK_FILE;
  }

  /**
   * Get current version lock
   */
  async getLock() {
    try {
      const data = await fs.readFile(this.lockFile, 'utf8');
      return JSON.parse(data);
    } catch (error) {
      // No lock file exists yet
      return {
        version: '1.0.0',
        generated: new Date().toISOString(),
        services: {},
        repositories: {}
      };
    }
  }

  /**
   * Save version lock
   */
  async saveLock(lock) {
    lock.generated = new Date().toISOString();
    await fs.mkdir(path.dirname(this.lockFile), { recursive: true });
    await fs.writeFile(this.lockFile, JSON.stringify(lock, null, 2));
  }

  /**
   * Get Docker image digest
   */
  getImageDigest(imageName, tag = 'latest') {
    try {
      const fullImage = `${imageName}:${tag}`;

      // Try to get from local Docker first
      try {
        const localDigest = execSync(
          `docker inspect --format='{{index .RepoDigests 0}}' ${fullImage}`,
          { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }
        ).trim();

        if (localDigest && localDigest !== '<no value>') {
          // Extract just the SHA256 part
          const match = localDigest.match(/sha256:[a-f0-9]{64}/);
          return match ? match[0] : null;
        }
      } catch (localError) {
        // Image not found locally, continue to ECR
      }

      // Try ECR
      const repoName = imageName.split('/').pop();
      const ecrDigest = execSync(
        `aws ecr describe-images --repository-name ${repoName} --image-ids imageTag=${tag} --query 'imageDetails[0].imageDigest' --output text`,
        { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }
      ).trim();

      return ecrDigest !== 'None' ? ecrDigest : null;
    } catch (error) {
      console.error(`Failed to get digest for ${imageName}:${tag}: ${error.message}`);
      return null;
    }
  }

  /**
   * Get Git commit for a repository
   */
  getGitCommit(repoPath) {
    try {
      const commit = execSync('git rev-parse HEAD', {
        cwd: repoPath,
        encoding: 'utf8'
      }).trim();
      return commit;
    } catch (error) {
      return null;
    }
  }

  /**
   * Get Git tag for a repository
   */
  getGitTag(repoPath) {
    try {
      const tag = execSync('git describe --tags --exact-match 2>/dev/null || echo ""', {
        cwd: repoPath,
        encoding: 'utf8'
      }).trim();
      return tag || null;
    } catch (error) {
      return null;
    }
  }

  /**
   * Lock a service version
   */
  async lockService(serviceName, options) {
    const {
      imageName,
      imageTag = 'latest',
      repoPath,
      version,
      metadata = {}
    } = options;

    const lock = await this.getLock();

    const digest = this.getImageDigest(imageName, imageTag);
    const gitCommit = repoPath ? this.getGitCommit(repoPath) : null;
    const gitTag = repoPath ? this.getGitTag(repoPath) : null;

    lock.services[serviceName] = {
      version: version || gitTag || gitCommit?.substring(0, 7) || 'unknown',
      image: {
        name: imageName,
        tag: imageTag,
        digest,
        fullRef: digest ? `${imageName}@${digest}` : `${imageName}:${imageTag}`
      },
      git: {
        commit: gitCommit,
        tag: gitTag,
        repoPath
      },
      locked: new Date().toISOString(),
      metadata
    };

    await this.saveLock(lock);

    return lock.services[serviceName];
  }

  /**
   * Lock a repository version
   */
  async lockRepository(repoName, repoPath) {
    const lock = await this.getLock();

    const commit = this.getGitCommit(repoPath);
    const tag = this.getGitTag(repoPath);

    // Get package.json version if it exists
    let packageVersion = null;
    try {
      const packageJson = JSON.parse(
        await fs.readFile(path.join(repoPath, 'package.json'), 'utf8')
      );
      packageVersion = packageJson.version;
    } catch (error) {
      // No package.json or no version field
    }

    lock.repositories[repoName] = {
      path: repoPath,
      version: packageVersion || tag || commit?.substring(0, 7) || 'unknown',
      git: {
        commit,
        tag
      },
      locked: new Date().toISOString()
    };

    await this.saveLock(lock);

    return lock.repositories[repoName];
  }

  /**
   * Lock all services from docker-compose file
   */
  async lockFromDockerCompose(composePath) {
    const composeContent = await fs.readFile(composePath, 'utf8');
    const yaml = require('js-yaml');
    const compose = yaml.load(composeContent);

    const results = [];

    for (const [serviceName, service] of Object.entries(compose.services || {})) {
      if (service.image) {
        const [imageName, imageTag] = service.image.split(':');

        const result = await this.lockService(serviceName, {
          imageName,
          imageTag: imageTag || 'latest',
          metadata: {
            source: 'docker-compose',
            composePath
          }
        });

        results.push(result);
      }
    }

    return results;
  }

  /**
   * Lock all repositories
   */
  async lockAllRepositories(baseDir) {
    const repos = [
      { name: 'aeims-control', path: path.join(baseDir, 'aeims-control') },
      { name: 'aeims', path: path.join(baseDir, 'aeims') },
      { name: 'aeims.app', path: path.join(baseDir, 'aeims.app') },
      { name: 'aeimsLib', path: path.join(baseDir, 'aeimsLib') }
    ];

    const results = [];

    for (const repo of repos) {
      try {
        const result = await this.lockRepository(repo.name, repo.path);
        results.push(result);
      } catch (error) {
        console.error(`Failed to lock ${repo.name}: ${error.message}`);
      }
    }

    return results;
  }

  /**
   * Verify lock integrity
   */
  async verifyLock() {
    const lock = await this.getLock();
    const issues = [];

    for (const [serviceName, serviceInfo] of Object.entries(lock.services)) {
      // Verify image digest still exists
      if (serviceInfo.image.digest) {
        const currentDigest = this.getImageDigest(
          serviceInfo.image.name,
          serviceInfo.image.tag
        );

        if (!currentDigest) {
          issues.push({
            service: serviceName,
            issue: 'IMAGE_NOT_FOUND',
            message: `Image ${serviceInfo.image.fullRef} not found`
          });
        } else if (currentDigest !== serviceInfo.image.digest) {
          issues.push({
            service: serviceName,
            issue: 'DIGEST_MISMATCH',
            message: `Image digest changed: ${serviceInfo.image.digest} → ${currentDigest}`,
            expected: serviceInfo.image.digest,
            actual: currentDigest
          });
        }
      }

      // Verify Git commit still exists
      if (serviceInfo.git?.commit && serviceInfo.git?.repoPath) {
        const currentCommit = this.getGitCommit(serviceInfo.git.repoPath);

        if (!currentCommit) {
          issues.push({
            service: serviceName,
            issue: 'REPO_NOT_FOUND',
            message: `Repository not found: ${serviceInfo.git.repoPath}`
          });
        } else if (currentCommit !== serviceInfo.git.commit) {
          issues.push({
            service: serviceName,
            issue: 'COMMIT_CHANGED',
            message: `Git commit changed: ${serviceInfo.git.commit} → ${currentCommit}`,
            expected: serviceInfo.git.commit,
            actual: currentCommit
          });
        }
      }
    }

    return {
      valid: issues.length === 0,
      issues,
      checkedServices: Object.keys(lock.services).length,
      timestamp: new Date().toISOString()
    };
  }

  /**
   * Update docker-compose with locked versions
   */
  async updateDockerCompose(composePath, outputPath = null) {
    const lock = await this.getLock();
    const composeContent = await fs.readFile(composePath, 'utf8');
    const yaml = require('js-yaml');
    const compose = yaml.load(composeContent);

    for (const [serviceName, service] of Object.entries(compose.services || {})) {
      const lockedService = lock.services[serviceName];

      if (lockedService && lockedService.image.digest) {
        // Use digest-based reference instead of tag
        service.image = lockedService.image.fullRef;
      }
    }

    const updatedCompose = yaml.dump(compose, { indent: 2, lineWidth: -1 });
    const output = outputPath || composePath;

    await fs.writeFile(output, updatedCompose);

    return output;
  }

  /**
   * Generate lock report
   */
  async generateReport() {
    const lock = await this.getLock();
    const verification = await this.verifyLock();

    let report = '\n=== VERSION LOCK REPORT ===\n\n';
    report += `Generated: ${lock.generated}\n`;
    report += `Lock Version: ${lock.version}\n\n`;

    report += '--- Services ---\n';
    for (const [serviceName, serviceInfo] of Object.entries(lock.services)) {
      report += `\n📦 ${serviceName}\n`;
      report += `   Version: ${serviceInfo.version}\n`;
      report += `   Image: ${serviceInfo.image.fullRef}\n`;
      report += `   Digest: ${serviceInfo.image.digest || 'N/A'}\n`;
      if (serviceInfo.git?.commit) {
        report += `   Git Commit: ${serviceInfo.git.commit}\n`;
      }
      if (serviceInfo.git?.tag) {
        report += `   Git Tag: ${serviceInfo.git.tag}\n`;
      }
      report += `   Locked: ${serviceInfo.locked}\n`;
    }

    report += '\n--- Repositories ---\n';
    for (const [repoName, repoInfo] of Object.entries(lock.repositories)) {
      report += `\n📁 ${repoName}\n`;
      report += `   Version: ${repoInfo.version}\n`;
      report += `   Path: ${repoInfo.path}\n`;
      if (repoInfo.git?.commit) {
        report += `   Git Commit: ${repoInfo.git.commit}\n`;
      }
      if (repoInfo.git?.tag) {
        report += `   Git Tag: ${repoInfo.git.tag}\n`;
      }
      report += `   Locked: ${repoInfo.locked}\n`;
    }

    report += '\n--- Verification ---\n';
    report += `Status: ${verification.valid ? '✅ VALID' : '❌ INVALID'}\n`;
    report += `Issues: ${verification.issues.length}\n`;

    if (verification.issues.length > 0) {
      report += '\nIssues:\n';
      for (const issue of verification.issues) {
        report += `  ⚠️  ${issue.service}: ${issue.message}\n`;
      }
    }

    return report;
  }
}

// CLI interface
if (require.main === module) {
  const manager = new VersionLockManager();

  const command = process.argv[2];
  const args = process.argv.slice(3);

  (async () => {
    switch (command) {
      case 'lock':
        const serviceName = args[0];
        const imageName = args[1];
        const imageTag = args[2] || 'latest';

        const result = await manager.lockService(serviceName, { imageName, imageTag });
        console.log(JSON.stringify(result, null, 2));
        break;

      case 'lock-compose':
        const composePath = args[0] || 'docker-compose-production.yml';
        const results = await manager.lockFromDockerCompose(composePath);
        console.log(`Locked ${results.length} services from ${composePath}`);
        break;

      case 'lock-repos':
        const baseDir = args[0] || path.join(require('os').homedir(), 'development');
        const repoResults = await manager.lockAllRepositories(baseDir);
        console.log(`Locked ${repoResults.length} repositories`);
        break;

      case 'verify':
        const verification = await manager.verifyLock();
        console.log(JSON.stringify(verification, null, 2));
        process.exit(verification.valid ? 0 : 1);
        break;

      case 'report':
        const report = await manager.generateReport();
        console.log(report);
        break;

      case 'update-compose':
        const inputCompose = args[0] || 'docker-compose-production.yml';
        const outputCompose = args[1];
        const updated = await manager.updateDockerCompose(inputCompose, outputCompose);
        console.log(`Updated: ${updated}`);
        break;

      default:
        console.log(`
Usage: version-lock.js <command> [args]

Commands:
  lock <service> <image> [tag]     Lock a service version
  lock-compose [file]              Lock all services from docker-compose
  lock-repos [base-dir]            Lock all repository versions
  verify                           Verify lock integrity (exits 1 if invalid)
  report                           Generate lock report
  update-compose [input] [output]  Update docker-compose with locked versions

Examples:
  version-lock.js lock admin-service 515966511618.dkr.ecr.us-east-1.amazonaws.com/admin latest
  version-lock.js lock-compose docker-compose-production.yml
  version-lock.js lock-repos /Users/ryan/development
  version-lock.js verify
  version-lock.js update-compose docker-compose-production.yml docker-compose-locked.yml
        `);
    }
  })().catch(err => {
    console.error('Error:', err.message);
    process.exit(1);
  });
}

module.exports = VersionLockManager;
