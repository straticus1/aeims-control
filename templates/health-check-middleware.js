/**
 * Standardized Health Check Middleware for AEIMS Services
 * Implements the AEIMS Health Check Specification
 */

const express = require('express');
const { promisify } = require('util');

class HealthCheckManager {
  constructor(config = {}) {
    this.serviceName = config.serviceName || 'unknown-service';
    this.version = config.version || '1.0.0';
    this.startTime = Date.now();
    this.checks = new Map();
    this.router = express.Router();
    this.setupRoutes();
  }

  // Register a health check
  registerCheck(name, checkFunction, options = {}) {
    this.checks.set(name, {
      fn: checkFunction,
      timeout: options.timeout || 5000,
      critical: options.critical !== false
    });
  }

  // Setup health check routes
  setupRoutes() {
    this.router.get('/health', this.basicHealthCheck.bind(this));
    this.router.get('/health/ready', this.readinessCheck.bind(this));
    this.router.get('/health/live', this.livenessCheck.bind(this));
    this.router.get('/health/deep', this.deepHealthCheck.bind(this));
  }

  // Basic health check
  async basicHealthCheck(req, res) {
    try {
      const checks = await this.runCriticalChecks();
      const status = this.determineStatus(checks);

      res.status(status === 'healthy' ? 200 : 503).json({
        status,
        timestamp: new Date().toISOString(),
        service: this.serviceName,
        version: this.version,
        uptime: Math.floor((Date.now() - this.startTime) / 1000),
        checks: this.simplifyChecks(checks)
      });
    } catch (error) {
      res.status(503).json({
        status: 'unhealthy',
        timestamp: new Date().toISOString(),
        service: this.serviceName,
        error: error.message
      });
    }
  }

  // Readiness check - is service ready to receive traffic?
  async readinessCheck(req, res) {
    try {
      const checks = await this.runCriticalChecks();
      const ready = Object.values(checks).every(check => check.status === 'healthy');

      res.status(ready ? 200 : 503).json({
        ready,
        timestamp: new Date().toISOString(),
        service: this.serviceName,
        checks: this.simplifyChecks(checks)
      });
    } catch (error) {
      res.status(503).json({
        ready: false,
        timestamp: new Date().toISOString(),
        service: this.serviceName,
        error: error.message
      });
    }
  }

  // Liveness check - is service alive?
  async livenessCheck(req, res) {
    // Simple check - if we can respond, we're alive
    res.status(200).json({
      alive: true,
      timestamp: new Date().toISOString(),
      service: this.serviceName,
      uptime: Math.floor((Date.now() - this.startTime) / 1000)
    });
  }

  // Deep health check - comprehensive check
  async deepHealthCheck(req, res) {
    try {
      const checks = await this.runAllChecks();
      const status = this.determineStatus(checks);

      res.status(status === 'healthy' ? 200 : 503).json({
        status,
        timestamp: new Date().toISOString(),
        service: this.serviceName,
        version: this.version,
        uptime: Math.floor((Date.now() - this.startTime) / 1000),
        checks
      });
    } catch (error) {
      res.status(503).json({
        status: 'unhealthy',
        timestamp: new Date().toISOString(),
        service: this.serviceName,
        error: error.message
      });
    }
  }

  // Run critical checks only
  async runCriticalChecks() {
    const criticalChecks = Array.from(this.checks.entries())
      .filter(([, config]) => config.critical);

    return await this.executeChecks(criticalChecks);
  }

  // Run all checks
  async runAllChecks() {
    const allChecks = Array.from(this.checks.entries());
    return await this.executeChecks(allChecks);
  }

  // Execute checks with timeout
  async executeChecks(checks) {
    const results = {};

    await Promise.all(checks.map(async ([name, config]) => {
      try {
        const timeoutPromise = new Promise((_, reject) =>
          setTimeout(() => reject(new Error('Timeout')), config.timeout)
        );

        const checkPromise = config.fn();
        const result = await Promise.race([checkPromise, timeoutPromise]);

        results[name] = {
          status: 'healthy',
          ...result
        };
      } catch (error) {
        results[name] = {
          status: 'unhealthy',
          error: error.message
        };
      }
    }));

    return results;
  }

  // Determine overall status
  determineStatus(checks) {
    const statuses = Object.values(checks).map(check => check.status);

    if (statuses.every(status => status === 'healthy')) {
      return 'healthy';
    } else if (statuses.some(status => status === 'healthy')) {
      return 'degraded';
    } else {
      return 'unhealthy';
    }
  }

  // Simplify checks for basic response
  simplifyChecks(checks) {
    const simplified = {};
    for (const [name, check] of Object.entries(checks)) {
      simplified[name] = check.status;
    }
    return simplified;
  }

  // Get router for mounting
  getRouter() {
    return this.router;
  }
}

// Common health check functions
const CommonChecks = {
  // Database health check
  database: (connection) => async () => {
    const start = Date.now();
    await connection.query('SELECT 1');
    const responseTime = Date.now() - start;

    // Get connection pool stats if available
    const poolStats = connection.pool ? {
      active: connection.pool.totalCount - connection.pool.idleCount,
      idle: connection.pool.idleCount,
      max: connection.pool.options.max
    } : null;

    return {
      response_time_ms: responseTime,
      connection_pool: poolStats
    };
  },

  // Redis health check
  redis: (client) => async () => {
    const start = Date.now();
    await client.ping();
    const responseTime = Date.now() - start;

    const info = await client.info('memory');
    const memoryMatch = info.match(/used_memory_human:(.+)/);
    const memoryUsage = memoryMatch ? memoryMatch[1].trim() : 'unknown';

    return {
      ping_response_ms: responseTime,
      memory_usage: memoryUsage,
      connected_clients: await client.info('clients').then(info => {
        const match = info.match(/connected_clients:(\d+)/);
        return match ? parseInt(match[1]) : 0;
      })
    };
  },

  // HTTP API health check
  httpApi: (name, url) => async () => {
    const axios = require('axios');
    const start = Date.now();

    const response = await axios.get(url, {
      timeout: 3000,
      validateStatus: (status) => status < 500
    });

    const responseTime = Date.now() - start;

    return {
      status: response.status < 400 ? 'healthy' : 'degraded',
      response_time_ms: responseTime,
      last_check: new Date().toISOString(),
      http_status: response.status
    };
  },

  // File system health check
  filesystem: (path) => async () => {
    const fs = require('fs').promises;
    const start = Date.now();

    await fs.access(path);
    const stats = await fs.stat(path);
    const responseTime = Date.now() - start;

    return {
      response_time_ms: responseTime,
      writable: true // Could add write test
    };
  }
};

module.exports = {
  HealthCheckManager,
  CommonChecks
};