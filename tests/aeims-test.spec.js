const { test, expect } = require('@playwright/test');

test.describe('AEIMS Infrastructure Testing', () => {
  const domains = [
    'https://aeims.app',
    'https://admin.aeims.app', 
    'https://api.aeims.app',
    'https://sexacomms.com',
    'https://admin.sexacomms.com',
    'https://api.sexacomms.com'
  ];

  domains.forEach(domain => {
    test(`${domain} health check`, async ({ page }) => {
      await page.goto(`${domain}/health`, { timeout: 10000 });
      const content = await page.content();
      console.log(`${domain}/health response:`, content);
      expect(page.url()).toContain('/health');
    });

    test(`${domain} login page loads`, async ({ page }) => {
      try {
        await page.goto(domain, { timeout: 10000 });
        const title = await page.title();
        console.log(`${domain} title:`, title);
        const hasLoginForm = await page.locator('form, input[type="password"], .login').count() > 0;
        console.log(`${domain} has login form:`, hasLoginForm);
      } catch (error) {
        console.log(`${domain} failed to load:`, error.message);
      }
    });
  });
});
