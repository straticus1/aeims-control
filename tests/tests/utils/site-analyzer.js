const fs = require('fs-extra');
const path = require('path');

class SiteAnalyzer {
  constructor() {
    this.results = [];
  }

  async analyzePage(page, url, testName) {
    const startTime = Date.now();
    const analysis = {
      url,
      testName,
      timestamp: new Date().toISOString(),
      performance: {},
      accessibility: {},
      seo: {},
      security: {},
      errors: [],
      warnings: []
    };

    try {
      // Navigate to page
      const response = await page.goto(url, { waitUntil: 'networkidle' });
      
      // Basic response analysis
      analysis.responseStatus = response.status();
      analysis.responseHeaders = response.headers();
      analysis.loadTime = Date.now() - startTime;

      // Check for JavaScript errors
      const errors = [];
      page.on('pageerror', (error) => {
        errors.push({
          type: 'JavaScript Error',
          message: error.message,
          stack: error.stack
        });
      });

      // Check for failed requests
      page.on('requestfailed', (request) => {
        errors.push({
          type: 'Failed Request',
          url: request.url(),
          failure: request.failure()?.errorText
        });
      });

      // Performance metrics
      const performanceMetrics = await page.evaluate(() => {
        const navigation = performance.getEntriesByType('navigation')[0];
        return {
          domContentLoaded: navigation.domContentLoadedEventEnd - navigation.domContentLoadedEventStart,
          loadComplete: navigation.loadEventEnd - navigation.loadEventStart,
          firstPaint: performance.getEntriesByName('first-paint')[0]?.startTime,
          firstContentfulPaint: performance.getEntriesByName('first-contentful-paint')[0]?.startTime,
          resourceCount: performance.getEntriesByType('resource').length
        };
      });
      analysis.performance = performanceMetrics;

      // SEO Analysis
      const seoData = await page.evaluate(() => {
        return {
          title: document.title,
          metaDescription: document.querySelector('meta[name="description"]')?.content,
          h1Count: document.querySelectorAll('h1').length,
          h2Count: document.querySelectorAll('h2').length,
          imgWithoutAlt: document.querySelectorAll('img:not([alt])').length,
          linksWithoutText: document.querySelectorAll('a:empty').length,
          canonicalTag: document.querySelector('link[rel="canonical"]')?.href
        };
      });
      analysis.seo = seoData;

      // Security headers analysis
      const securityHeaders = {
        'content-security-policy': response.headers()['content-security-policy'],
        'x-frame-options': response.headers()['x-frame-options'],
        'x-content-type-options': response.headers()['x-content-type-options'],
        'strict-transport-security': response.headers()['strict-transport-security'],
        'x-xss-protection': response.headers()['x-xss-protection']
      };
      analysis.security = securityHeaders;

      // Accessibility checks
      const accessibilityIssues = await page.evaluate(() => {
        const issues = [];
        
        // Check for missing alt attributes
        const imagesWithoutAlt = document.querySelectorAll('img:not([alt])');
        if (imagesWithoutAlt.length > 0) {
          issues.push(`${imagesWithoutAlt.length} images missing alt attributes`);
        }
        
        // Check for empty links
        const emptyLinks = document.querySelectorAll('a:empty');
        if (emptyLinks.length > 0) {
          issues.push(`${emptyLinks.length} empty links found`);
        }
        
        // Check for missing labels on form inputs
        const inputsWithoutLabels = document.querySelectorAll('input:not([aria-label]):not([aria-labelledby])');
        const unlabeledInputs = Array.from(inputsWithoutLabels).filter(input => {
          const id = input.id;
          return !id || !document.querySelector(`label[for="${id}"]`);
        });
        if (unlabeledInputs.length > 0) {
          issues.push(`${unlabeledInputs.length} form inputs missing labels`);
        }
        
        return issues;
      });
      analysis.accessibility.issues = accessibilityIssues;

      // Check for forms and login functionality
      const formsData = await page.evaluate(() => {
        const forms = Array.from(document.querySelectorAll('form'));
        return forms.map(form => ({
          action: form.action,
          method: form.method,
          inputCount: form.querySelectorAll('input').length,
          hasPasswordField: form.querySelector('input[type="password"]') !== null,
          hasEmailField: form.querySelector('input[type="email"]') !== null,
          hasSubmitButton: form.querySelector('input[type="submit"], button[type="submit"]') !== null
        }));
      });
      analysis.forms = formsData;

      // Collect all errors
      analysis.errors = errors;

      this.results.push(analysis);
      return analysis;

    } catch (error) {
      analysis.errors.push({
        type: 'Analysis Error',
        message: error.message,
        stack: error.stack
      });
      
      this.results.push(analysis);
      return analysis;
    }
  }

  async generateReport() {
    const reportPath = path.join(__dirname, '..', 'test-results', 'site-analysis-report.json');
    await fs.ensureDir(path.dirname(reportPath));
    
    const report = {
      generatedAt: new Date().toISOString(),
      totalSitesTested: this.results.length,
      summary: this.generateSummary(),
      details: this.results
    };

    await fs.writeJson(reportPath, report, { spaces: 2 });
    return report;
  }

  generateSummary() {
    return {
      averageLoadTime: this.results.reduce((sum, r) => sum + (r.loadTime || 0), 0) / this.results.length,
      sitesWithErrors: this.results.filter(r => r.errors.length > 0).length,
      sitesWithAccessibilityIssues: this.results.filter(r => r.accessibility.issues?.length > 0).length,
      sitesWithForms: this.results.filter(r => r.forms?.length > 0).length,
      sitesWithLoginForms: this.results.filter(r => r.forms?.some(f => f.hasPasswordField)).length,
      httpStatusCodes: this.results.reduce((acc, r) => {
        const status = r.responseStatus;
        acc[status] = (acc[status] || 0) + 1;
        return acc;
      }, {})
    };
  }
}

module.exports = SiteAnalyzer;
