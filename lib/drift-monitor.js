#!/usr/bin/env node

/**
 * Drift Monitoring Service
 *
 * Continuously monitors for configuration drift and sends alerts.
 * Can run as a daemon or be executed periodically via cron.
 */

const DriftDetector = require('./drift-detector');
const ManifestTracker = require('./manifest-tracker');
const fs = require('fs').promises;
const path = require('path');

const ALERT_FILE = path.join(__dirname, '../.aeims/drift-alerts.json');
const ALERT_THRESHOLD = {
  CRITICAL: 0,  // Alert immediately
  HIGH: 1,      // Alert if > 1 HIGH severity drifts
  MEDIUM: 5,    // Alert if > 5 MEDIUM severity drifts
  LOW: 10       // Alert if > 10 LOW severity drifts
};

class DriftMonitor {
  constructor(options = {}) {
    this.driftDetector = new DriftDetector();
    this.manifestTracker = new ManifestTracker();
    this.interval = options.interval || 300000; // 5 minutes default
    this.clusterName = options.clusterName || 'aeims-cluster-production';
    this.alertHandlers = options.alertHandlers || [];
    this.running = false;
  }

  /**
   * Check drift and generate alerts
   */
  async checkDrift() {
    const results = await this.driftDetector.detectAllDrift(this.clusterName);

    const alerts = [];

    // Check CRITICAL drifts
    if (results.criticalDrifts > ALERT_THRESHOLD.CRITICAL) {
      alerts.push({
        severity: 'CRITICAL',
        message: `${results.criticalDrifts} CRITICAL drift(s) detected`,
        count: results.criticalDrifts,
        services: results.services
          .filter(s => s.severity === 'CRITICAL')
          .map(s => s.serviceName)
      });
    }

    // Check HIGH drifts
    if (results.highDrifts > ALERT_THRESHOLD.HIGH) {
      alerts.push({
        severity: 'HIGH',
        message: `${results.highDrifts} HIGH severity drift(s) detected`,
        count: results.highDrifts,
        services: results.services
          .filter(s => s.severity === 'HIGH')
          .map(s => s.serviceName)
      });
    }

    // Check MEDIUM drifts
    if (results.mediumDrifts > ALERT_THRESHOLD.MEDIUM) {
      alerts.push({
        severity: 'MEDIUM',
        message: `${results.mediumDrifts} MEDIUM severity drift(s) detected`,
        count: results.mediumDrifts,
        services: results.services
          .filter(s => s.severity === 'MEDIUM')
          .map(s => s.serviceName)
      });
    }

    // Check total services with drift
    const driftPercentage = (results.servicesWithDrift / results.totalServices) * 100;
    if (driftPercentage > 50) {
      alerts.push({
        severity: 'HIGH',
        message: `${driftPercentage.toFixed(1)}% of services have drift (${results.servicesWithDrift}/${results.totalServices})`,
        count: results.servicesWithDrift,
        percentage: driftPercentage
      });
    }

    const alertData = {
      timestamp: new Date().toISOString(),
      cluster: this.clusterName,
      alerts,
      driftResults: results
    };

    // Save alerts
    if (alerts.length > 0) {
      await this.saveAlerts(alertData);
      await this.sendAlerts(alertData);
    }

    return alertData;
  }

  /**
   * Save alerts to file
   */
  async saveAlerts(alertData) {
    let history = [];

    try {
      const existing = await fs.readFile(ALERT_FILE, 'utf8');
      history = JSON.parse(existing);
    } catch (error) {
      // File doesn't exist yet
    }

    history.unshift(alertData);

    // Keep last 100 alerts
    if (history.length > 100) {
      history = history.slice(0, 100);
    }

    await fs.writeFile(ALERT_FILE, JSON.stringify(history, null, 2));
  }

  /**
   * Send alerts via configured handlers
   */
  async sendAlerts(alertData) {
    for (const handler of this.alertHandlers) {
      try {
        await handler(alertData);
      } catch (error) {
        console.error(`Alert handler failed: ${error.message}`);
      }
    }

    // Default console logging
    if (this.alertHandlers.length === 0) {
      console.log('\n⚠️  DRIFT ALERTS ⚠️\n');
      console.log(`Timestamp: ${alertData.timestamp}`);
      console.log(`Cluster: ${alertData.cluster}\n`);

      for (const alert of alertData.alerts) {
        console.log(`[${alert.severity}] ${alert.message}`);
        if (alert.services && alert.services.length > 0) {
          console.log(`  Services: ${alert.services.join(', ')}`);
        }
        console.log();
      }
    }
  }

  /**
   * Start monitoring daemon
   */
  async start() {
    console.log(`Starting drift monitor (interval: ${this.interval}ms)`);
    this.running = true;

    await this.manifestTracker.initialize();

    while (this.running) {
      try {
        console.log(`\n[${new Date().toISOString()}] Checking for drift...`);

        const alertData = await this.checkDrift();

        if (alertData.alerts.length === 0) {
          console.log('✅ No alerts');
        } else {
          console.log(`⚠️  ${alertData.alerts.length} alert(s) generated`);
        }
      } catch (error) {
        console.error(`Error during drift check: ${error.message}`);
      }

      // Wait for next interval
      await this.sleep(this.interval);
    }
  }

  /**
   * Stop monitoring daemon
   */
  stop() {
    console.log('Stopping drift monitor...');
    this.running = false;
  }

  /**
   * Sleep helper
   */
  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * Get alert history
   */
  async getAlertHistory(limit = 10) {
    try {
      const data = await fs.readFile(ALERT_FILE, 'utf8');
      const history = JSON.parse(data);
      return history.slice(0, limit);
    } catch (error) {
      return [];
    }
  }

  /**
   * Clear alert history
   */
  async clearAlerts() {
    await fs.writeFile(ALERT_FILE, JSON.stringify([], null, 2));
  }
}

// Slack alert handler example
function createSlackHandler(webhookUrl) {
  return async (alertData) => {
    const { execSync } = require('child_process');

    const color = {
      'CRITICAL': 'danger',
      'HIGH': 'warning',
      'MEDIUM': '#FFA500',
      'LOW': '#00BFFF'
    };

    const attachments = alertData.alerts.map(alert => ({
      color: color[alert.severity] || 'warning',
      title: `${alert.severity} Drift Alert`,
      text: alert.message,
      fields: alert.services ? [{
        title: 'Affected Services',
        value: alert.services.join(', '),
        short: false
      }] : [],
      footer: `Cluster: ${alertData.cluster}`,
      ts: Math.floor(new Date(alertData.timestamp).getTime() / 1000)
    }));

    const payload = {
      text: '⚠️  Configuration Drift Detected',
      attachments
    };

    execSync(`curl -X POST -H 'Content-type: application/json' --data '${JSON.stringify(payload)}' ${webhookUrl}`, {
      encoding: 'utf8'
    });
  };
}

// Email alert handler example
function createEmailHandler(emailConfig) {
  return async (alertData) => {
    const { execSync } = require('child_process');

    let message = `Configuration Drift Alert\n\n`;
    message += `Timestamp: ${alertData.timestamp}\n`;
    message += `Cluster: ${alertData.cluster}\n\n`;

    for (const alert of alertData.alerts) {
      message += `[${alert.severity}] ${alert.message}\n`;
      if (alert.services && alert.services.length > 0) {
        message += `Services: ${alert.services.join(', ')}\n`;
      }
      message += '\n';
    }

    // Use AWS SES or sendmail
    execSync(`echo "${message}" | mail -s "AEIMS Drift Alert" ${emailConfig.to}`, {
      encoding: 'utf8'
    });
  };
}

// CLI interface
if (require.main === module) {
  const command = process.argv[2];
  const args = process.argv.slice(3);

  const monitor = new DriftMonitor({
    interval: parseInt(process.env.DRIFT_CHECK_INTERVAL) || 300000,
    clusterName: process.env.CLUSTER_NAME || 'aeims-cluster-production'
  });

  // Add alert handlers if configured
  if (process.env.SLACK_WEBHOOK_URL) {
    monitor.alertHandlers.push(createSlackHandler(process.env.SLACK_WEBHOOK_URL));
  }

  if (process.env.ALERT_EMAIL) {
    monitor.alertHandlers.push(createEmailHandler({ to: process.env.ALERT_EMAIL }));
  }

  (async () => {
    switch (command) {
      case 'start':
        await monitor.start();
        break;

      case 'check':
        const result = await monitor.checkDrift();
        console.log(JSON.stringify(result, null, 2));
        process.exit(result.alerts.length > 0 ? 1 : 0);
        break;

      case 'history':
        const limit = parseInt(args[0]) || 10;
        const history = await monitor.getAlertHistory(limit);
        console.log(JSON.stringify(history, null, 2));
        break;

      case 'clear':
        await monitor.clearAlerts();
        console.log('Alert history cleared');
        break;

      default:
        console.log(`
Usage: drift-monitor.js <command> [args]

Commands:
  start                Start monitoring daemon
  check                Check drift once and exit (exits 1 if alerts)
  history [limit]      Show alert history (default: 10)
  clear                Clear alert history

Environment Variables:
  DRIFT_CHECK_INTERVAL   Check interval in milliseconds (default: 300000 = 5 min)
  CLUSTER_NAME          AWS ECS cluster name (default: aeims-cluster-production)
  SLACK_WEBHOOK_URL     Slack webhook for alerts
  ALERT_EMAIL           Email address for alerts

Examples:
  # Start daemon
  drift-monitor.js start

  # Check once (good for cron)
  drift-monitor.js check

  # View recent alerts
  drift-monitor.js history 20

  # Run with custom interval (1 minute)
  DRIFT_CHECK_INTERVAL=60000 drift-monitor.js start

  # Send alerts to Slack
  SLACK_WEBHOOK_URL=https://hooks.slack.com/... drift-monitor.js start
        `);
    }
  })().catch(err => {
    console.error('Error:', err.message);
    process.exit(1);
  });

  // Handle shutdown gracefully
  process.on('SIGINT', () => {
    monitor.stop();
    process.exit(0);
  });
  process.on('SIGTERM', () => {
    monitor.stop();
    process.exit(0);
  });
}

module.exports = DriftMonitor;
module.exports.createSlackHandler = createSlackHandler;
module.exports.createEmailHandler = createEmailHandler;
