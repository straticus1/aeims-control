// test-helpers.js
const fs = require('fs-extra');
const path = require('path');

class TestHelpers {
  constructor(page, testInfo) {
    this.page = page;
    this.testInfo = testInfo;
    this.consoleErrors = [];
    this.networkErrors = [];
    this.screenshots = [];
  }

  async setupErrorMonitoring() {
    // Monitor console errors
    this.page.on('console', (msg) => {
      if (msg.type() === 'error') {
        this.consoleErrors.push({
          timestamp: new Date().toISOString(),
          message: msg.text(),
          url: this.page.url()
        });
      }
    });

    // Monitor network failures
    this.page.on('requestfailed', (request) => {
      this.networkErrors.push({
        timestamp: new Date().toISOString(),
        url: request.url(),
        method: request.method(),
        failure: request.failure()?.errorText || 'Unknown error',
        resourceType: request.resourceType()
      });
    });

    // Monitor unhandled promise rejections
    this.page.on('pageerror', (error) => {
      this.consoleErrors.push({
        timestamp: new Date().toISOString(),
        message: `Unhandled Promise Rejection: ${error.message}`,
        stack: error.stack,
        url: this.page.url()
      });
    });
  }

  async takeScreenshot(name, options = {}) {
    try {
      const screenshotName = `${this.testInfo.title.replace(/\s+/g, '-')}-${name}`;
      const screenshotPath = path.join('test-results', 'screenshots', `${screenshotName}.png`);

      await this.page.screenshot({
        path: screenshotPath,
        fullPage: options.fullPage !== false,
        ...options
      });

      this.screenshots.push({
        name: screenshotName,
        path: screenshotPath,
        timestamp: new Date().toISOString(),
        url: this.page.url(),
        viewport: this.page.viewportSize()
      });

      return screenshotPath;
    } catch (error) {
      console.error(`Failed to take screenshot ${name}:`, error.message);
      return null;
    }
  }

  async waitForPageLoad(timeout = 30000) {
    try {
      await this.page.waitForLoadState('networkidle', { timeout });
      await this.page.waitForLoadState('domcontentloaded', { timeout });
    } catch (error) {
      console.warn('Page load timeout:', error.message);
    }
  }

  async checkAccessibility() {
    // Basic accessibility checks
    const issues = [];

    try {
      // Check for missing alt text on images
      const imagesWithoutAlt = await this.page.locator('img:not([alt])').count();
      if (imagesWithoutAlt > 0) {
        issues.push(`${imagesWithoutAlt} images missing alt text`);
      }

      // Check for form inputs without labels
      const inputsWithoutLabels = await this.page.locator('input:not([aria-label]):not([aria-labelledby]):not([id])').count();
      if (inputsWithoutLabels > 0) {
        issues.push(`${inputsWithoutLabels} form inputs without proper labels`);
      }

      // Check for missing page title
      const title = await this.page.title();
      if (!title || title.trim() === '') {
        issues.push('Page missing title');
      }

      // Check for heading structure
      const h1Count = await this.page.locator('h1').count();
      if (h1Count === 0) {
        issues.push('Page missing H1 heading');
      } else if (h1Count > 1) {
        issues.push(`Page has ${h1Count} H1 headings (should have only 1)`);
      }

    } catch (error) {
      issues.push(`Accessibility check failed: ${error.message}`);
    }

    return issues;
  }

  async checkPerformance() {
    const metrics = {};

    try {
      // Get navigation timing
      const navigationTiming = await this.page.evaluate(() => {
        const perfData = performance.getEntriesByType('navigation')[0];
        return {
          domContentLoaded: perfData.domContentLoadedEventEnd - perfData.domContentLoadedEventStart,
          loadComplete: perfData.loadEventEnd - perfData.loadEventStart,
          totalPageLoad: perfData.loadEventEnd - perfData.fetchStart
        };
      });

      metrics.navigationTiming = navigationTiming;

      // Get resource timing
      const resourceTiming = await this.page.evaluate(() => {
        const resources = performance.getEntriesByType('resource');
        return resources.map(resource => ({
          name: resource.name,
          type: resource.initiatorType,
          size: resource.transferSize,
          duration: resource.duration
        }));
      });

      metrics.resourceTiming = resourceTiming;

      // Calculate performance score
      const totalLoadTime = navigationTiming.totalPageLoad;
      let score = 'excellent';
      if (totalLoadTime > 3000) score = 'poor';
      else if (totalLoadTime > 1500) score = 'fair';
      else if (totalLoadTime > 500) score = 'good';

      metrics.performanceScore = {
        score,
        totalLoadTime,
        benchmark: {
          excellent: '< 500ms',
          good: '< 1.5s',
          fair: '< 3s',
          poor: '> 3s'
        }
      };

    } catch (error) {
      metrics.error = `Performance check failed: ${error.message}`;
    }

    return metrics;
  }

  async checkSEO() {
    const seoIssues = [];

    try {
      // Check meta description
      const metaDescription = await this.page.locator('meta[name="description"]').getAttribute('content');
      if (!metaDescription || metaDescription.length < 50 || metaDescription.length > 160) {
        seoIssues.push('Meta description missing or not optimal length (50-160 chars)');
      }

      // Check title length
      const title = await this.page.title();
      if (title && (title.length < 30 || title.length > 60)) {
        seoIssues.push('Page title not optimal length (30-60 chars)');
      }

      // Check for meta viewport
      const hasViewport = await this.page.locator('meta[name="viewport"]').count() > 0;
      if (!hasViewport) {
        seoIssues.push('Missing meta viewport tag');
      }

      // Check for canonical URL
      const hasCanonical = await this.page.locator('link[rel="canonical"]').count() > 0;
      if (!hasCanonical) {
        seoIssues.push('Missing canonical URL');
      }

      // Check for Open Graph tags
      const hasOgTitle = await this.page.locator('meta[property="og:title"]').count() > 0;
      const hasOgDescription = await this.page.locator('meta[property="og:description"]').count() > 0;
      if (!hasOgTitle || !hasOgDescription) {
        seoIssues.push('Missing or incomplete Open Graph tags');
      }

    } catch (error) {
      seoIssues.push(`SEO check failed: ${error.message}`);
    }

    return seoIssues;
  }

  async checkLinks() {
    const linkIssues = [];

    try {
      const links = await this.page.locator('a[href]').all();

      for (let i = 0; i < Math.min(links.length, 50); i++) { // Limit to 50 links for performance
        const link = links[i];
        const href = await link.getAttribute('href');
        const text = await link.textContent();

        if (!href) continue;

        // Check for empty link text
        if (!text || text.trim() === '') {
          linkIssues.push(`Link with empty text: ${href}`);
        }

        // Check for suspicious hrefs
        if (href === '#' || href === 'javascript:void(0)') {
          linkIssues.push(`Placeholder link found: ${href}`);
        }

        // Check external links for target="_blank" and rel="noopener"
        if (href.startsWith('http') && !href.includes('aeims.app')) {
          const target = await link.getAttribute('target');
          const rel = await link.getAttribute('rel');

          if (target === '_blank' && (!rel || !rel.includes('noopener'))) {
            linkIssues.push(`External link missing rel="noopener": ${href}`);
          }
        }
      }

    } catch (error) {
      linkIssues.push(`Link check failed: ${error.message}`);
    }

    return linkIssues;
  }

  async generateTestReport() {
    const report = {
      testInfo: {
        title: this.testInfo.title,
        project: this.testInfo.project.name,
        url: this.page.url(),
        timestamp: new Date().toISOString(),
        viewport: this.page.viewportSize()
      },
      errors: {
        console: this.consoleErrors,
        network: this.networkErrors
      },
      screenshots: this.screenshots,
      accessibility: await this.checkAccessibility(),
      performance: await this.checkPerformance(),
      seo: await this.checkSEO(),
      links: await this.checkLinks()
    };

    // Save individual test report
    const reportPath = path.join('test-results', `${this.testInfo.title.replace(/\s+/g, '-')}-report.json`);
    await fs.ensureDir(path.dirname(reportPath));
    await fs.writeJson(reportPath, report, { spaces: 2 });

    return report;
  }

  getErrorSummary() {
    return {
      consoleErrors: this.consoleErrors.length,
      networkErrors: this.networkErrors.length,
      hasErrors: this.consoleErrors.length > 0 || this.networkErrors.length > 0
    };
  }
}

// Utility functions
const utils = {
  async waitForElement(page, selector, options = {}) {
    const timeout = options.timeout || 10000;
    try {
      await page.waitForSelector(selector, { timeout, ...options });
      return true;
    } catch (error) {
      console.warn(`Element not found: ${selector}`);
      return false;
    }
  },

  async isElementVisible(page, selector) {
    try {
      const element = await page.locator(selector);
      return await element.isVisible();
    } catch (error) {
      return false;
    }
  },

  async getElementText(page, selector) {
    try {
      const element = await page.locator(selector);
      return await element.textContent();
    } catch (error) {
      return null;
    }
  },

  async clickIfVisible(page, selector, options = {}) {
    try {
      const element = page.locator(selector);
      if (await element.isVisible()) {
        await element.click(options);
        return true;
      }
      return false;
    } catch (error) {
      console.warn(`Failed to click element: ${selector}`);
      return false;
    }
  },

  async scrollToBottom(page) {
    await page.evaluate(() => {
      window.scrollTo(0, document.body.scrollHeight);
    });
    await page.waitForTimeout(1000); // Wait for any lazy-loaded content
  },

  async scrollToTop(page) {
    await page.evaluate(() => {
      window.scrollTo(0, 0);
    });
    await page.waitForTimeout(500);
  }
};

module.exports = { TestHelpers, utils };