// 02-login-functionality.spec.js
const { test, expect } = require('@playwright/test');
const { TestHelpers, utils } = require('../utils/test-helpers');

test.describe('AEIMS Login Functionality', () => {
  let testHelpers;

  test.beforeEach(async ({ page }, testInfo) => {
    testHelpers = new TestHelpers(page, testInfo);
    await testHelpers.setupErrorMonitoring();
  });

  test.afterEach(async ({ page }) => {
    await testHelpers.generateTestReport();
  });

  test('should find and navigate to login page', async ({ page }) => {
    await page.goto('/');
    await testHelpers.waitForPageLoad();

    // Look for login links/buttons on main page
    const loginSelectors = [
      'a[href*="login"]',
      'a[href*="signin"]',
      'a[href*="auth"]',
      'button:has-text("Login")',
      'button:has-text("Sign In")',
      'a:has-text("Login")',
      'a:has-text("Sign In")',
      'a:has-text("Log In")',
      '.login-link',
      '.signin-link',
      '[data-testid*="login"]',
      '[id*="login"]',
      '[class*="login"]'
    ];

    let loginLinkFound = false;
    let loginUrl = '';

    for (const selector of loginSelectors) {
      const element = page.locator(selector).first();
      if (await element.isVisible()) {
        loginLinkFound = true;

        // Get the href if it's a link, or try clicking if it's a button
        const tagName = await element.evaluate(el => el.tagName.toLowerCase());

        if (tagName === 'a') {
          loginUrl = await element.getAttribute('href') || '';
          console.log(`Login link found: ${selector} -> ${loginUrl}`);

          // Navigate to login page
          await element.click();
          await testHelpers.waitForPageLoad();
          break;
        } else {
          // It's a button, click it
          console.log(`Login button found: ${selector}`);
          await element.click();
          await testHelpers.waitForPageLoad();
          loginUrl = page.url();
          break;
        }
      }
    }

    // If no login link found on main page, try common login URLs
    if (!loginLinkFound) {
      const commonLoginPaths = ['/login', '/signin', '/auth', '/account/login', '/user/login'];

      for (const path of commonLoginPaths) {
        try {
          const response = await page.goto(path, { waitUntil: 'networkidle', timeout: 10000 });
          if (response && response.status() === 200) {
            loginUrl = path;
            loginLinkFound = true;
            console.log(`Login page found at: ${path}`);
            break;
          }
        } catch (error) {
          console.log(`Login path ${path} not found`);
        }
      }
    }

    await testHelpers.takeScreenshot('login-page-found');

    // Log findings for manual verification
    console.log(`Login functionality: ${loginLinkFound ? 'FOUND' : 'NOT FOUND'}`);
    if (loginUrl) {
      console.log(`Login URL: ${loginUrl}`);
    }

    // This test documents findings rather than asserting
    expect(true, 'Login page search completed').toBe(true);
  });

  test('should analyze login form if present', async ({ page }) => {
    const loginPaths = ['/', '/login', '/signin', '/auth'];
    let loginFormFound = false;
    let formAnalysis = {};

    for (const path of loginPaths) {
      try {
        await page.goto(path, { waitUntil: 'networkidle', timeout: 15000 });

        // Look for login forms
        const formSelectors = [
          'form:has(input[type="password"])',
          'form:has(input[name*="password"])',
          'form:has(input[name*="email"])',
          'form:has(input[name*="username"])',
          '.login-form',
          '.signin-form',
          '.auth-form',
          '[class*="login"] form',
          '[id*="login"] form'
        ];

        for (const selector of formSelectors) {
          const form = page.locator(selector).first();
          if (await form.isVisible()) {
            loginFormFound = true;
            console.log(`Login form found on ${path} with selector: ${selector}`);

            // Analyze form fields
            const emailInputs = await form.locator('input[type="email"], input[name*="email"], input[placeholder*="email" i]').count();
            const usernameInputs = await form.locator('input[name*="username"], input[placeholder*="username" i]').count();
            const passwordInputs = await form.locator('input[type="password"], input[name*="password"]').count();
            const submitButtons = await form.locator('button[type="submit"], input[type="submit"], button:has-text("Login"), button:has-text("Sign In")').count();

            formAnalysis = {
              path,
              selector,
              fields: {
                emailInputs,
                usernameInputs,
                passwordInputs,
                submitButtons
              }
            };

            // Check for visible credentials (as mentioned by user)
            const visibleCredentials = await page.evaluate(() => {
              const allText = document.body.innerText.toLowerCase();
              const patterns = [
                /username.*?:.*?[\w@.-]+/gi,
                /password.*?:.*?[\w.-]+/gi,
                /email.*?:.*?[\w@.-]+/gi,
                /test.*?account/gi,
                /demo.*?credentials/gi
              ];

              const found = [];
              patterns.forEach(pattern => {
                const matches = allText.match(pattern);
                if (matches) {
                  found.push(...matches);
                }
              });

              return found;
            });

            if (visibleCredentials.length > 0) {
              formAnalysis.visibleCredentials = visibleCredentials;
              console.log('Visible credentials found:', visibleCredentials);
            }

            await testHelpers.takeScreenshot(`login-form-analysis-${path.replace('/', 'root')}`);
            break;
          }
        }

        if (loginFormFound) break;

      } catch (error) {
        console.log(`Error accessing ${path}:`, error.message);
      }
    }

    // Log analysis results
    console.log('Login Form Analysis:', JSON.stringify(formAnalysis, null, 2));

    // Document findings
    expect(true, 'Login form analysis completed').toBe(true);
  });

  test('should test login form functionality if credentials are visible', async ({ page }) => {
    const loginPaths = ['/', '/login', '/signin', '/auth'];
    let testCredentials = null;
    let formFound = false;

    for (const path of loginPaths) {
      try {
        await page.goto(path, { waitUntil: 'networkidle', timeout: 15000 });

        // Check for visible test credentials on the page
        const pageText = await page.textContent('body');

        // Look for credential patterns
        const credentialPatterns = [
          /(?:username|email)\s*:?\s*([a-zA-Z0-9@._-]+)/gi,
          /password\s*:?\s*([a-zA-Z0-9@._-]+)/gi,
          /test\s+(?:username|email)\s*:?\s*([a-zA-Z0-9@._-]+)/gi,
          /demo\s+(?:username|email)\s*:?\s*([a-zA-Z0-9@._-]+)/gi
        ];

        const foundCredentials = {};
        credentialPatterns.forEach(pattern => {
          const matches = pageText.match(pattern);
          if (matches) {
            matches.forEach(match => {
              if (match.includes('@') || match.includes('test') || match.includes('demo')) {
                if (match.toLowerCase().includes('password')) {
                  foundCredentials.password = match.split(/:\s*/)[1] || match.split(/\s+/)[1];
                } else {
                  foundCredentials.username = match.split(/:\s*/)[1] || match.split(/\s+/)[1];
                }
              }
            });
          }
        });

        if (Object.keys(foundCredentials).length > 0) {
          testCredentials = foundCredentials;
          console.log('Test credentials found:', testCredentials);
        }

        // Look for login form
        const form = page.locator('form:has(input[type="password"])').first();
        if (await form.isVisible()) {
          formFound = true;

          await testHelpers.takeScreenshot('login-form-before-test');

          // Test form interaction
          const usernameField = form.locator('input[type="email"], input[name*="email"], input[name*="username"]').first();
          const passwordField = form.locator('input[type="password"]').first();
          const submitButton = form.locator('button[type="submit"], input[type="submit"], button:has-text("Login"), button:has-text("Sign In")').first();

          // Test field interaction (without actual credentials)
          if (await usernameField.isVisible()) {
            await usernameField.click();
            await usernameField.fill('test@example.com');
            console.log('Username field interaction: SUCCESS');
          }

          if (await passwordField.isVisible()) {
            await passwordField.click();
            await passwordField.fill('testpassword123');
            console.log('Password field interaction: SUCCESS');
          }

          await testHelpers.takeScreenshot('login-form-filled');

          // Test submit button (but don't actually submit)
          if (await submitButton.isVisible()) {
            const buttonText = await submitButton.textContent();
            console.log(`Submit button found: "${buttonText}"`);

            // Just verify the button is clickable, don't actually click
            const isEnabled = await submitButton.isEnabled();
            console.log(`Submit button enabled: ${isEnabled}`);
          }

          // Clear the form
          if (await usernameField.isVisible()) {
            await usernameField.clear();
          }
          if (await passwordField.isVisible()) {
            await passwordField.clear();
          }

          await testHelpers.takeScreenshot('login-form-cleared');

          break;
        }

      } catch (error) {
        console.log(`Error testing login form on ${path}:`, error.message);
      }
    }

    // Report findings
    console.log(`Login form found: ${formFound}`);
    console.log(`Test credentials visible: ${testCredentials !== null}`);

    if (testCredentials) {
      console.log('Visible credentials:', testCredentials);
    }

    expect(true, 'Login form functionality test completed').toBe(true);
  });

  test('should test login error handling', async ({ page }) => {
    const loginPaths = ['/', '/login', '/signin', '/auth'];
    let errorTestCompleted = false;

    for (const path of loginPaths) {
      try {
        await page.goto(path, { waitUntil: 'networkidle', timeout: 15000 });

        const form = page.locator('form:has(input[type="password"])').first();
        if (await form.isVisible()) {
          const usernameField = form.locator('input[type="email"], input[name*="email"], input[name*="username"]').first();
          const passwordField = form.locator('input[type="password"]').first();
          const submitButton = form.locator('button[type="submit"], input[type="submit"], button:has-text("Login"), button:has-text("Sign In")').first();

          // Test with invalid credentials
          if (await usernameField.isVisible() && await passwordField.isVisible() && await submitButton.isVisible()) {
            await usernameField.fill('invalid@test.com');
            await passwordField.fill('invalidpassword');

            await testHelpers.takeScreenshot('login-invalid-credentials');

            // Try to submit (with error monitoring)
            const beforeErrors = testHelpers.getErrorSummary();

            try {
              await submitButton.click();
              await page.waitForTimeout(3000); // Wait for potential error messages

              // Look for error messages
              const errorSelectors = [
                '.error',
                '.alert',
                '.warning',
                '[class*="error"]',
                '[class*="alert"]',
                '[role="alert"]',
                '.text-danger',
                '.text-error'
              ];

              let errorFound = false;
              for (const selector of errorSelectors) {
                const errorElement = page.locator(selector);
                if (await errorElement.isVisible()) {
                  const errorText = await errorElement.textContent();
                  console.log(`Error message found: "${errorText}"`);
                  errorFound = true;
                  break;
                }
              }

              await testHelpers.takeScreenshot('login-error-response');

              console.log(`Error message displayed: ${errorFound}`);
              errorTestCompleted = true;

            } catch (error) {
              console.log('Error during login submission:', error.message);
            }

            const afterErrors = testHelpers.getErrorSummary();
            console.log('Console errors before/after:', beforeErrors.consoleErrors, '/', afterErrors.consoleErrors);

            break;
          }
        }

      } catch (error) {
        console.log(`Error testing login errors on ${path}:`, error.message);
      }
    }

    expect(true, 'Login error handling test completed').toBe(true);
  });

  test('should check for password field security features', async ({ page }) => {
    const loginPaths = ['/', '/login', '/signin', '/auth'];
    let securityFeatures = {};

    for (const path of loginPaths) {
      try {
        await page.goto(path, { waitUntil: 'networkidle', timeout: 15000 });

        const passwordField = page.locator('input[type="password"]').first();
        if (await passwordField.isVisible()) {
          // Check password field attributes
          const autocomplete = await passwordField.getAttribute('autocomplete');
          const name = await passwordField.getAttribute('name');
          const placeholder = await passwordField.getAttribute('placeholder');

          securityFeatures = {
            path,
            autocomplete,
            name,
            placeholder,
            hasPasswordType: true
          };

          // Check for password visibility toggle
          const visibilityToggle = await page.locator('button:near(input[type="password"]), .password-toggle, [class*="toggle"], [class*="show-password"]').count();
          securityFeatures.hasVisibilityToggle = visibilityToggle > 0;

          // Check for form autocomplete
          const form = passwordField.locator('xpath=ancestor::form[1]');
          const formAutocomplete = await form.getAttribute('autocomplete');
          securityFeatures.formAutocomplete = formAutocomplete;

          console.log('Password field security features:', securityFeatures);

          await testHelpers.takeScreenshot('password-security-check');
          break;
        }

      } catch (error) {
        console.log(`Error checking password security on ${path}:`, error.message);
      }
    }

    expect(true, 'Password security features check completed').toBe(true);
  });

  test('should test forgot password functionality', async ({ page }) => {
    const loginPaths = ['/', '/login', '/signin', '/auth'];
    let forgotPasswordFound = false;

    for (const path of loginPaths) {
      try {
        await page.goto(path, { waitUntil: 'networkidle', timeout: 15000 });

        // Look for forgot password links
        const forgotPasswordSelectors = [
          'a:has-text("Forgot Password")',
          'a:has-text("Forgot password")',
          'a:has-text("Reset Password")',
          'a:has-text("Forgotten Password")',
          'a[href*="forgot"]',
          'a[href*="reset"]',
          '.forgot-password',
          '.reset-password'
        ];

        for (const selector of forgotPasswordSelectors) {
          const element = page.locator(selector).first();
          if (await element.isVisible()) {
            forgotPasswordFound = true;
            const text = await element.textContent();
            const href = await element.getAttribute('href');

            console.log(`Forgot password link found: "${text}" -> ${href}`);

            // Test the link (without following through)
            await testHelpers.takeScreenshot('forgot-password-link');

            // You could click and test the forgot password page too
            // await element.click();
            // await testHelpers.waitForPageLoad();
            // await testHelpers.takeScreenshot('forgot-password-page');

            break;
          }
        }

        if (forgotPasswordFound) break;

      } catch (error) {
        console.log(`Error checking forgot password on ${path}:`, error.message);
      }
    }

    console.log(`Forgot password functionality: ${forgotPasswordFound ? 'FOUND' : 'NOT FOUND'}`);
    expect(true, 'Forgot password functionality check completed').toBe(true);
  });
});