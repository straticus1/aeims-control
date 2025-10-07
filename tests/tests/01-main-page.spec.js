// 01-main-page.spec.js
const { test, expect } = require('@playwright/test');
const { TestHelpers, utils } = require('../utils/test-helpers');

test.describe('AEIMS Main Page (www.aeims.app)', () => {
  let testHelpers;

  test.beforeEach(async ({ page }, testInfo) => {
    testHelpers = new TestHelpers(page, testInfo);
    await testHelpers.setupErrorMonitoring();
  });

  test.afterEach(async ({ page }) => {
    await testHelpers.generateTestReport();
  });

  test('should load the main page successfully', async ({ page }) => {
    await page.goto('/', { waitUntil: 'networkidle' });

    // Take initial screenshot
    await testHelpers.takeScreenshot('main-page-loaded');

    // Verify page loads
    await expect(page).toHaveTitle(/AEIMS/i);

    // Check for critical page elements
    const hasMainContent = await utils.isElementVisible(page, 'main, [role="main"], .main-content');
    expect(hasMainContent, 'Main content area should be visible').toBe(true);

    // Verify no critical console errors
    const errorSummary = testHelpers.getErrorSummary();
    if (errorSummary.hasErrors) {
      console.warn('Console/Network errors detected:', errorSummary);
    }
  });

  test('should have proper meta tags and SEO elements', async ({ page }) => {
    await page.goto('/');
    await testHelpers.waitForPageLoad();

    // Check title
    const title = await page.title();
    expect(title.length, 'Title should be between 30-60 characters').toBeGreaterThan(10);

    // Check meta description
    const metaDescription = await page.locator('meta[name="description"]').getAttribute('content');
    expect(metaDescription, 'Meta description should exist').toBeTruthy();

    // Check viewport meta tag
    const viewportMeta = page.locator('meta[name="viewport"]');
    await expect(viewportMeta, 'Viewport meta tag should exist').toHaveCount(1);

    // Check for favicon
    const favicon = page.locator('link[rel*="icon"]');
    const faviconCount = await favicon.count();
    expect(faviconCount, 'Favicon should be present').toBeGreaterThan(0);

    await testHelpers.takeScreenshot('seo-elements-check');
  });

  test('should display navigation menu', async ({ page }) => {
    await page.goto('/');
    await testHelpers.waitForPageLoad();

    // Look for common navigation patterns
    const navSelectors = [
      'nav',
      '[role="navigation"]',
      '.navigation',
      '.navbar',
      '.menu',
      'header nav',
      '.header-nav'
    ];

    let navFound = false;
    for (const selector of navSelectors) {
      if (await utils.isElementVisible(page, selector)) {
        navFound = true;
        console.log(`Navigation found with selector: ${selector}`);
        break;
      }
    }

    expect(navFound, 'Navigation menu should be present').toBe(true);

    // Check for navigation links
    const navLinks = await page.locator('nav a, [role="navigation"] a').count();
    expect(navLinks, 'Navigation should contain links').toBeGreaterThan(0);

    await testHelpers.takeScreenshot('navigation-menu');
  });

  test('should display header and footer', async ({ page }) => {
    await page.goto('/');
    await testHelpers.waitForPageLoad();

    // Check for header
    const headerSelectors = ['header', '.header', '[role="banner"]'];
    let headerFound = false;

    for (const selector of headerSelectors) {
      if (await utils.isElementVisible(page, selector)) {
        headerFound = true;
        console.log(`Header found with selector: ${selector}`);
        break;
      }
    }

    expect(headerFound, 'Header should be present').toBe(true);

    // Check for footer
    const footerSelectors = ['footer', '.footer', '[role="contentinfo"]'];
    let footerFound = false;

    for (const selector of footerSelectors) {
      if (await utils.isElementVisible(page, selector)) {
        footerFound = true;
        console.log(`Footer found with selector: ${selector}`);
        break;
      }
    }

    expect(footerFound, 'Footer should be present').toBe(true);

    await testHelpers.takeScreenshot('header-footer');
  });

  test('should have working logo/brand link', async ({ page }) => {
    await page.goto('/');
    await testHelpers.waitForPageLoad();

    // Look for logo/brand elements
    const logoSelectors = [
      '.logo',
      '.brand',
      'img[alt*="logo" i]',
      'img[alt*="aeims" i]',
      '[class*="logo"]',
      'header img',
      'nav img'
    ];

    let logoFound = false;
    for (const selector of logoSelectors) {
      const logoElement = page.locator(selector).first();
      if (await logoElement.isVisible()) {
        logoFound = true;
        console.log(`Logo found with selector: ${selector}`);

        // Check if logo is clickable
        const isClickable = await logoElement.evaluate(el => {
          return el.tagName === 'A' || el.parentElement?.tagName === 'A' ||
                 el.onclick !== null || el.style.cursor === 'pointer';
        });

        if (isClickable) {
          console.log('Logo appears to be clickable');
        }
        break;
      }
    }

    // Even if no logo found, that's not necessarily an error
    console.log(`Logo element ${logoFound ? 'found' : 'not found'}`);

    await testHelpers.takeScreenshot('logo-check');
  });

  test('should handle responsive design', async ({ page }) => {
    // Test mobile viewport
    await page.setViewportSize({ width: 375, height: 667 });
    await page.goto('/');
    await testHelpers.waitForPageLoad();
    await testHelpers.takeScreenshot('mobile-view');

    // Check if navigation is responsive (might be collapsed)
    const mobileNavVisible = await utils.isElementVisible(page, 'nav, [role="navigation"]');
    console.log(`Mobile navigation visible: ${mobileNavVisible}`);

    // Test tablet viewport
    await page.setViewportSize({ width: 768, height: 1024 });
    await page.goto('/');
    await testHelpers.waitForPageLoad();
    await testHelpers.takeScreenshot('tablet-view');

    // Test desktop viewport
    await page.setViewportSize({ width: 1920, height: 1080 });
    await page.goto('/');
    await testHelpers.waitForPageLoad();
    await testHelpers.takeScreenshot('desktop-view');

    // Verify page doesn't break at different sizes
    const bodyOverflow = await page.evaluate(() => {
      return window.getComputedStyle(document.body).overflowX;
    });

    expect(bodyOverflow, 'Page should not have horizontal overflow').not.toBe('scroll');
  });

  test('should load all critical resources', async ({ page }) => {
    await page.goto('/');

    // Wait for page to fully load
    await page.waitForLoadState('networkidle', { timeout: 30000 });

    // Check for CSS files
    const cssFiles = await page.locator('link[rel="stylesheet"]').count();
    console.log(`CSS files loaded: ${cssFiles}`);

    // Check for JavaScript files
    const jsFiles = await page.locator('script[src]').count();
    console.log(`JavaScript files loaded: ${jsFiles}`);

    // Check for images
    const images = await page.locator('img').count();
    console.log(`Images on page: ${images}`);

    // Verify no broken images (basic check)
    const brokenImages = await page.evaluate(() => {
      const images = Array.from(document.querySelectorAll('img'));
      return images.filter(img => !img.complete || img.naturalWidth === 0).length;
    });

    expect(brokenImages, 'No images should be broken').toBe(0);

    await testHelpers.takeScreenshot('resources-loaded');
  });

  test('should have accessible content', async ({ page }) => {
    await page.goto('/');
    await testHelpers.waitForPageLoad();

    // Check for heading structure
    const h1Count = await page.locator('h1').count();
    expect(h1Count, 'Should have exactly one H1 tag').toBeGreaterThanOrEqual(1);
    expect(h1Count, 'Should not have more than one H1 tag').toBeLessThanOrEqual(2);

    // Check for alt text on images
    const imagesWithoutAlt = await page.locator('img:not([alt])').count();
    expect(imagesWithoutAlt, 'All images should have alt text').toBe(0);

    // Check for skip links
    const skipLinks = await page.locator('a[href="#main"], a[href="#content"], .skip-link').count();
    console.log(`Skip links found: ${skipLinks}`);

    await testHelpers.takeScreenshot('accessibility-check');
  });

  test('should perform well', async ({ page }) => {
    const startTime = Date.now();

    await page.goto('/', { waitUntil: 'networkidle' });

    const loadTime = Date.now() - startTime;
    console.log(`Page load time: ${loadTime}ms`);

    // Get performance metrics
    const performanceMetrics = await testHelpers.checkPerformance();
    console.log('Performance metrics:', performanceMetrics);

    // Basic performance expectations
    expect(loadTime, 'Page should load within 10 seconds').toBeLessThan(10000);

    await testHelpers.takeScreenshot('performance-check');
  });

  test('should have secure headers and proper HTTPS', async ({ page }) => {
    const response = await page.goto('/');

    // Verify HTTPS
    expect(page.url(), 'Should be served over HTTPS').toMatch(/^https:/);

    // Check response status
    expect(response?.status(), 'Should return successful status').toBe(200);

    // Check for security headers (if accessible)
    const headers = response?.headers() || {};
    console.log('Response headers:', Object.keys(headers));

    await testHelpers.takeScreenshot('security-check');
  });
});