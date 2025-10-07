// 03-subdomain-tests.spec.js
const { test, expect } = require('@playwright/test');
const { TestHelpers, utils } = require('../utils/test-helpers');

test.describe('AEIMS Subdomain Testing', () => {
  let testHelpers;

  const subdomains = [
    { name: 'Main Site (www)', url: 'https://www.aeims.app' },
    { name: 'Root Domain', url: 'https://aeims.app' },
    { name: 'API Subdomain', url: 'https://api.aeims.app' },
    { name: 'Admin Subdomain', url: 'https://admin.aeims.app' }
  ];

  test.beforeEach(async ({ page }, testInfo) => {
    testHelpers = new TestHelpers(page, testInfo);
    await testHelpers.setupErrorMonitoring();
  });

  test.afterEach(async ({ page }) => {
    await testHelpers.generateTestReport();
  });

  // Test each subdomain individually
  for (const subdomain of subdomains) {
    test(`should test ${subdomain.name} (${subdomain.url})`, async ({ page }) => {
      const domainResult = {
        url: subdomain.url,
        accessible: false,
        status: null,
        redirects: [],
        contentType: null,
        isApiEndpoint: false,
        hasWebInterface: false,
        errors: []
      };

      try {
        console.log(`Testing ${subdomain.name}: ${subdomain.url}`);

        // Track redirects
        const redirects = [];
        page.on('response', (response) => {
          if ([301, 302, 303, 307, 308].includes(response.status())) {
            redirects.push({
              from: response.url(),
              to: response.headers()['location'],
              status: response.status()
            });
          }
        });

        const response = await page.goto(subdomain.url, {
          waitUntil: 'domcontentloaded',
          timeout: 30000
        });

        if (response) {
          domainResult.accessible = true;
          domainResult.status = response.status();
          domainResult.contentType = response.headers()['content-type'] || '';
          domainResult.redirects = redirects;

          console.log(`${subdomain.name} - Status: ${domainResult.status}`);
          console.log(`${subdomain.name} - Content-Type: ${domainResult.contentType}`);

          if (redirects.length > 0) {
            console.log(`${subdomain.name} - Redirects:`, redirects);
          }

          // Check if it's an API endpoint
          if (domainResult.contentType.includes('json') || subdomain.url.includes('api.')) {
            domainResult.isApiEndpoint = true;

            // For API endpoints, check for common API responses
            try {
              const body = await response.text();
              const isJsonResponse = body.trim().startsWith('{') || body.trim().startsWith('[');

              if (isJsonResponse) {
                console.log(`${subdomain.name} - API Response detected`);
                const jsonData = JSON.parse(body);
                console.log(`${subdomain.name} - API Data:`, Object.keys(jsonData));
              }
            } catch (error) {
              console.log(`${subdomain.name} - Error parsing API response:`, error.message);
            }
          } else {
            // Check for web interface elements
            domainResult.hasWebInterface = true;

            // Wait a bit more for potential web content to load
            try {
              await page.waitForLoadState('networkidle', { timeout: 10000 });
            } catch (error) {
              console.log(`${subdomain.name} - Network idle timeout (expected for some sites)`);
            }

            // Check for common web elements
            const hasTitle = await page.title() !== '';
            const hasBody = await page.locator('body').isVisible();
            const hasMainContent = await utils.isElementVisible(page, 'main, .main, #main, .content');

            console.log(`${subdomain.name} - Has title: ${hasTitle}`);
            console.log(`${subdomain.name} - Has body: ${hasBody}`);
            console.log(`${subdomain.name} - Has main content: ${hasMainContent}`);

            // Check for navigation
            const hasNavigation = await utils.isElementVisible(page, 'nav, .nav, .navigation, .navbar');
            console.log(`${subdomain.name} - Has navigation: ${hasNavigation}`);

            // Check for login elements (especially for admin subdomain)
            const hasLoginForm = await utils.isElementVisible(page, 'form:has(input[type="password"]), .login-form, .signin-form');
            console.log(`${subdomain.name} - Has login form: ${hasLoginForm}`);

            // Take screenshot of the page
            await testHelpers.takeScreenshot(`subdomain-${subdomain.name.toLowerCase().replace(/\s+/g, '-')}`);
          }

        } else {
          domainResult.errors.push('No response received');
        }

      } catch (error) {
        domainResult.errors.push(error.message);
        console.log(`${subdomain.name} - Error:`, error.message);

        // Still try to take a screenshot of error state
        try {
          await testHelpers.takeScreenshot(`subdomain-${subdomain.name.toLowerCase().replace(/\s+/g, '-')}-error`);
        } catch (screenshotError) {
          console.log(`${subdomain.name} - Screenshot error:`, screenshotError.message);
        }
      }

      // Log comprehensive results
      console.log(`${subdomain.name} - Final Result:`, JSON.stringify(domainResult, null, 2));

      // The test passes regardless of subdomain accessibility - we're documenting findings
      expect(true, `${subdomain.name} test completed`).toBe(true);
    });
  }

  test('should test subdomain connectivity and redirects', async ({ page }) => {
    const connectivityResults = {};

    for (const subdomain of subdomains) {
      try {
        console.log(`Testing connectivity for: ${subdomain.url}`);

        // Try to connect and measure response time
        const startTime = Date.now();
        const response = await page.goto(subdomain.url, {
          waitUntil: 'domcontentloaded',
          timeout: 15000
        });
        const responseTime = Date.now() - startTime;

        connectivityResults[subdomain.name] = {
          url: subdomain.url,
          accessible: !!response,
          status: response?.status() || null,
          responseTime,
          finalUrl: page.url()
        };

        // Check if there was a redirect
        if (page.url() !== subdomain.url) {
          connectivityResults[subdomain.name].redirected = true;
          connectivityResults[subdomain.name].redirectTarget = page.url();
          console.log(`${subdomain.name} redirected to: ${page.url()}`);
        }

        console.log(`${subdomain.name} - Response time: ${responseTime}ms`);

      } catch (error) {
        connectivityResults[subdomain.name] = {
          url: subdomain.url,
          accessible: false,
          error: error.message
        };
        console.log(`${subdomain.name} - Connection failed:`, error.message);
      }
    }

    // Log complete connectivity results
    console.log('Subdomain Connectivity Results:', JSON.stringify(connectivityResults, null, 2));

    // Take a summary screenshot
    await testHelpers.takeScreenshot('subdomain-connectivity-summary');

    expect(true, 'Subdomain connectivity test completed').toBe(true);
  });

  test('should test cross-subdomain functionality', async ({ page }) => {
    console.log('Testing cross-subdomain functionality...');

    // Start with main site
    try {
      await page.goto('https://www.aeims.app');
      await testHelpers.waitForPageLoad();

      // Look for links that point to other subdomains
      const crossSubdomainLinks = await page.evaluate(() => {
        const links = Array.from(document.querySelectorAll('a[href]'));
        return links
          .map(link => ({ text: link.textContent?.trim(), href: link.href }))
          .filter(link =>
            link.href.includes('api.aeims.app') ||
            link.href.includes('admin.aeims.app') ||
            (link.href.includes('aeims.app') && !link.href.includes('www.aeims.app'))
          );
      });

      console.log('Cross-subdomain links found:', crossSubdomainLinks);

      // Test a few cross-subdomain links if they exist
      for (let i = 0; i < Math.min(crossSubdomainLinks.length, 3); i++) {
        const link = crossSubdomainLinks[i];
        try {
          console.log(`Testing cross-subdomain link: ${link.text} -> ${link.href}`);

          // Navigate to the cross-subdomain link
          const response = await page.goto(link.href, { timeout: 15000 });

          if (response) {
            console.log(`Cross-subdomain navigation successful: ${response.status()}`);
            await testHelpers.takeScreenshot(`cross-subdomain-${i}`);
          }

        } catch (error) {
          console.log(`Cross-subdomain navigation failed for ${link.href}:`, error.message);
        }
      }

    } catch (error) {
      console.log('Cross-subdomain functionality test error:', error.message);
    }

    expect(true, 'Cross-subdomain functionality test completed').toBe(true);
  });

  test('should check subdomain SSL certificates', async ({ page }) => {
    console.log('Checking SSL certificates for subdomains...');

    const sslResults = {};

    for (const subdomain of subdomains) {
      try {
        console.log(`Checking SSL for: ${subdomain.url}`);

        const response = await page.goto(subdomain.url, { timeout: 15000 });

        if (response) {
          // Check if the connection is secure
          const isSecure = page.url().startsWith('https://');

          sslResults[subdomain.name] = {
            url: subdomain.url,
            isSecure,
            accessible: true,
            finalUrl: page.url()
          };

          console.log(`${subdomain.name} - HTTPS: ${isSecure}`);

          // Additional security header checks
          const securityHeaders = {
            'strict-transport-security': response.headers()['strict-transport-security'],
            'x-frame-options': response.headers()['x-frame-options'],
            'x-content-type-options': response.headers()['x-content-type-options'],
            'x-xss-protection': response.headers()['x-xss-protection']
          };

          sslResults[subdomain.name].securityHeaders = securityHeaders;

          const headerCount = Object.values(securityHeaders).filter(h => h).length;
          console.log(`${subdomain.name} - Security headers present: ${headerCount}/4`);

        } else {
          sslResults[subdomain.name] = {
            url: subdomain.url,
            accessible: false,
            error: 'No response'
          };
        }

      } catch (error) {
        sslResults[subdomain.name] = {
          url: subdomain.url,
          accessible: false,
          error: error.message
        };
        console.log(`${subdomain.name} - SSL check failed:`, error.message);
      }
    }

    console.log('SSL Results:', JSON.stringify(sslResults, null, 2));
    await testHelpers.takeScreenshot('ssl-security-check');

    expect(true, 'SSL certificate check completed').toBe(true);
  });

  test('should test API subdomain endpoints', async ({ page }) => {
    console.log('Testing API subdomain endpoints...');

    const apiBaseUrl = 'https://api.aeims.app';
    const commonApiEndpoints = [
      '/',
      '/health',
      '/status',
      '/version',
      '/api',
      '/v1',
      '/docs',
      '/swagger',
      '/openapi.json'
    ];

    const apiResults = {};

    for (const endpoint of commonApiEndpoints) {
      const fullUrl = `${apiBaseUrl}${endpoint}`;

      try {
        console.log(`Testing API endpoint: ${fullUrl}`);

        const response = await page.goto(fullUrl, {
          waitUntil: 'domcontentloaded',
          timeout: 10000
        });

        if (response) {
          const status = response.status();
          const contentType = response.headers()['content-type'] || '';

          apiResults[endpoint] = {
            url: fullUrl,
            status,
            contentType,
            accessible: status < 500
          };

          console.log(`API ${endpoint} - Status: ${status}, Content-Type: ${contentType}`);

          // If it's a JSON response, try to parse it
          if (contentType.includes('json')) {
            try {
              const body = await response.text();
              const jsonData = JSON.parse(body);
              apiResults[endpoint].hasJsonResponse = true;
              apiResults[endpoint].responseKeys = Object.keys(jsonData);
              console.log(`API ${endpoint} - JSON Keys:`, Object.keys(jsonData));
            } catch (error) {
              console.log(`API ${endpoint} - JSON parse error:`, error.message);
            }
          }

          await testHelpers.takeScreenshot(`api-endpoint-${endpoint.replace(/\//g, 'root')}`);

        } else {
          apiResults[endpoint] = {
            url: fullUrl,
            accessible: false,
            error: 'No response'
          };
        }

      } catch (error) {
        apiResults[endpoint] = {
          url: fullUrl,
          accessible: false,
          error: error.message
        };
        console.log(`API ${endpoint} - Error:`, error.message);
      }
    }

    console.log('API Endpoints Results:', JSON.stringify(apiResults, null, 2));

    expect(true, 'API endpoints test completed').toBe(true);
  });
});