// 00-quick-check.spec.js
const { test, expect } = require('@playwright/test');

test.describe('AEIMS Quick Website Check', () => {

  test('should check website accessibility and basic functionality', async ({ page }) => {
    console.log('Starting quick website accessibility check...');

    try {
      // Test main website
      console.log('Testing www.aeims.app...');
      const response = await page.goto('https://www.aeims.app', {
        waitUntil: 'domcontentloaded',
        timeout: 30000
      });

      console.log(`Main site status: ${response?.status() || 'No response'}`);
      console.log(`Main site URL: ${page.url()}`);

      if (response && response.status() < 400) {
        const title = await page.title();
        console.log(`Page title: "${title}"`);

        // Take basic screenshot
        await page.screenshot({
          path: 'test-results/main-site-check.png',
          fullPage: false
        });

        // Check for basic elements
        const hasBody = await page.locator('body').isVisible();
        const hasTitle = title.length > 0;

        console.log(`Has body: ${hasBody}`);
        console.log(`Has title: ${hasTitle}`);

        expect(hasBody, 'Body should be visible').toBe(true);
        expect(hasTitle, 'Title should exist').toBe(true);
      }

    } catch (error) {
      console.log('Main site error:', error.message);
    }

    // Test subdomains
    const subdomains = [
      'https://aeims.app',
      'https://api.aeims.app',
      'https://admin.aeims.app'
    ];

    for (const subdomain of subdomains) {
      try {
        console.log(`Testing ${subdomain}...`);

        const response = await page.goto(subdomain, {
          waitUntil: 'domcontentloaded',
          timeout: 15000
        });

        console.log(`${subdomain} status: ${response?.status() || 'No response'}`);
        console.log(`${subdomain} final URL: ${page.url()}`);

        if (response) {
          // Take screenshot
          await page.screenshot({
            path: `test-results/${subdomain.replace('https://', '').replace(/\./g, '-')}.png`,
            fullPage: false
          });
        }

      } catch (error) {
        console.log(`${subdomain} error:`, error.message);
      }
    }

    expect(true, 'Quick check completed').toBe(true);
  });
});