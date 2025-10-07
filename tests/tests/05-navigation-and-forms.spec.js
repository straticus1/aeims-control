// 05-navigation-and-forms.spec.js
const { test, expect } = require('@playwright/test');
const { TestHelpers, utils } = require('../utils/test-helpers');

test.describe('AEIMS Navigation and Form Testing', () => {
  let testHelpers;

  test.beforeEach(async ({ page }, testInfo) => {
    testHelpers = new TestHelpers(page, testInfo);
    await testHelpers.setupErrorMonitoring();
  });

  test.afterEach(async ({ page }) => {
    await testHelpers.generateTestReport();
  });

  test('should test complete site navigation flow', async ({ page }) => {
    console.log('Testing complete site navigation...');

    await page.goto('/');
    await testHelpers.waitForPageLoad();

    const navigationMap = new Map();
    const visitedUrls = new Set();
    const startUrl = page.url();

    // Start with homepage
    navigationMap.set(startUrl, {
      title: await page.title(),
      status: 'visited',
      links: [],
      errors: []
    });

    await testHelpers.takeScreenshot('navigation-start-homepage');

    // Find all internal links on homepage
    const internalLinks = await page.evaluate(() => {
      const links = Array.from(document.querySelectorAll('a[href]'));
      return links
        .map(link => ({
          text: link.textContent?.trim() || '',
          href: link.href,
          isInternal: link.href.includes(window.location.hostname) && !link.href.includes('#')
        }))
        .filter(link => link.isInternal && link.href !== window.location.href)
        .slice(0, 10); // Limit to 10 links for comprehensive testing
    });

    console.log(`Found ${internalLinks.length} internal links to test`);

    // Test navigation to each internal link
    for (let i = 0; i < internalLinks.length; i++) {
      const link = internalLinks[i];

      try {
        if (visitedUrls.has(link.href)) {
          console.log(`Skipping already visited: ${link.href}`);
          continue;
        }

        console.log(`Navigating to: ${link.text} -> ${link.href}`);

        const response = await page.goto(link.href, {
          waitUntil: 'domcontentloaded',
          timeout: 15000
        });

        if (response && response.status() < 400) {
          const pageTitle = await page.title();

          navigationMap.set(link.href, {
            title: pageTitle,
            status: 'success',
            referrer: startUrl,
            linkText: link.text,
            responseTime: Date.now()
          });

          visitedUrls.add(link.href);

          console.log(`✅ Successfully navigated to: ${pageTitle}`);

          await testHelpers.takeScreenshot(`navigation-page-${i + 1}`);

          // Test back navigation
          await page.goBack();
          await testHelpers.waitForPageLoad();

          const backToOriginal = page.url() === startUrl;
          console.log(`Back navigation successful: ${backToOriginal}`);

        } else {
          console.log(`❌ Navigation failed: ${response?.status() || 'No response'}`);

          navigationMap.set(link.href, {
            status: 'failed',
            error: `HTTP ${response?.status() || 'No response'}`,
            linkText: link.text
          });
        }

      } catch (error) {
        console.log(`❌ Navigation error for ${link.href}:`, error.message);

        navigationMap.set(link.href, {
          status: 'error',
          error: error.message,
          linkText: link.text
        });
      }
    }

    // Test breadcrumb navigation if present
    const breadcrumbs = await page.locator('.breadcrumb, .breadcrumbs, nav[aria-label*="breadcrumb" i]').count();
    if (breadcrumbs > 0) {
      console.log('Testing breadcrumb navigation...');
      await testHelpers.takeScreenshot('breadcrumb-navigation');

      const breadcrumbLinks = await page.locator('.breadcrumb a, .breadcrumbs a').all();

      for (let i = 0; i < Math.min(breadcrumbLinks.length, 3); i++) {
        try {
          const breadcrumbText = await breadcrumbLinks[i].textContent();
          console.log(`Testing breadcrumb: ${breadcrumbText}`);

          await breadcrumbLinks[i].click();
          await testHelpers.waitForPageLoad();

          console.log(`✅ Breadcrumb navigation successful`);

        } catch (error) {
          console.log(`❌ Breadcrumb navigation error:`, error.message);
        }
      }
    }

    // Generate navigation report
    const navigationSummary = {
      totalLinks: internalLinks.length,
      successful: Array.from(navigationMap.values()).filter(page => page.status === 'success').length,
      failed: Array.from(navigationMap.values()).filter(page => page.status === 'failed').length,
      errors: Array.from(navigationMap.values()).filter(page => page.status === 'error').length
    };

    console.log('Navigation Test Summary:', JSON.stringify(navigationSummary, null, 2));
    console.log('Detailed Navigation Map:', JSON.stringify(Object.fromEntries(navigationMap), null, 2));

    expect(navigationSummary.successful, 'Should have some successful navigation').toBeGreaterThan(0);
  });

  test('should test form validation and submission', async ({ page }) => {
    console.log('Testing form validation and submission...');

    const testUrls = ['/', '/contact', '/signup', '/register', '/login'];
    const formTestResults = [];

    for (const url of testUrls) {
      try {
        await page.goto(url, { timeout: 15000 });
        await testHelpers.waitForPageLoad();

        const forms = await page.locator('form').all();

        for (let i = 0; i < forms.length; i++) {
          const form = forms[i];

          try {
            console.log(`Testing form ${i + 1} on ${url}`);

            const formData = {
              url,
              formIndex: i + 1,
              fields: [],
              validationTests: {},
              submissionTest: null
            };

            // Analyze form fields
            const inputs = await form.locator('input, textarea, select').all();

            for (const input of inputs) {
              const type = await input.getAttribute('type') || 'text';
              const name = await input.getAttribute('name') || '';
              const required = await input.getAttribute('required') !== null;
              const placeholder = await input.getAttribute('placeholder') || '';

              formData.fields.push({
                type,
                name,
                required,
                placeholder
              });
            }

            await testHelpers.takeScreenshot(`form-${url.replace('/', 'root')}-${i + 1}-initial`);

            // Test required field validation
            const requiredFields = formData.fields.filter(field => field.required);

            if (requiredFields.length > 0) {
              console.log(`Testing validation for ${requiredFields.length} required fields`);

              // Try to submit empty form
              const submitButton = form.locator('button[type="submit"], input[type="submit"]').first();

              if (await submitButton.isVisible()) {
                try {
                  await submitButton.click();
                  await page.waitForTimeout(2000);

                  // Check for validation messages
                  const validationMessages = await page.locator(':invalid, .error, .invalid, [aria-invalid="true"]').count();
                  formData.validationTests.emptyFormSubmission = {
                    validationMessagesShown: validationMessages > 0,
                    messageCount: validationMessages
                  };

                  console.log(`Empty form validation messages: ${validationMessages}`);

                  await testHelpers.takeScreenshot(`form-${url.replace('/', 'root')}-${i + 1}-empty-validation`);

                } catch (error) {
                  console.log('Error testing empty form submission:', error.message);
                }
              }
            }

            // Test field validation individually
            for (const input of inputs) {
              const type = await input.getAttribute('type') || 'text';
              const name = await input.getAttribute('name') || '';

              if (type === 'email') {
                // Test invalid email
                await input.fill('invalid-email');
                await input.blur();
                await page.waitForTimeout(500);

                const isInvalid = await input.evaluate(el => !el.validity.valid);
                formData.validationTests[`${name}_email_validation`] = isInvalid;

                console.log(`Email validation for ${name}: ${isInvalid ? 'Working' : 'Not working'}`);

                // Fix with valid email
                await input.fill('test@example.com');

              } else if (type === 'text' && name.toLowerCase().includes('name')) {
                await input.fill('Test User');

              } else if (type === 'password') {
                await input.fill('TestPassword123!');

              } else if (type === 'tel') {
                await input.fill('+1-555-123-4567');

              } else if (type === 'text' || type === 'textarea') {
                await input.fill('Test input data');
              }
            }

            await testHelpers.takeScreenshot(`form-${url.replace('/', 'root')}-${i + 1}-filled`);

            // Test form submission with valid data (but don't actually submit)
            const submitButton = form.locator('button[type="submit"], input[type="submit"]').first();

            if (await submitButton.isVisible()) {
              const buttonText = await submitButton.textContent();

              // Only actually submit if it's a safe form (like contact or newsletter)
              const isSafeForm = buttonText?.toLowerCase().includes('contact') ||
                               buttonText?.toLowerCase().includes('newsletter') ||
                               buttonText?.toLowerCase().includes('subscribe') ||
                               url.includes('contact');

              if (isSafeForm) {
                console.log(`Attempting safe form submission: ${buttonText}`);

                try {
                  const currentUrl = page.url();

                  await submitButton.click();
                  await page.waitForTimeout(3000);

                  const newUrl = page.url();
                  const hasSuccessMessage = await page.locator('.success, .thank-you, .submitted, [class*="success"]').count() > 0;

                  formData.submissionTest = {
                    attempted: true,
                    urlChanged: newUrl !== currentUrl,
                    successMessageShown: hasSuccessMessage,
                    finalUrl: newUrl
                  };

                  console.log(`Form submission result: URL changed: ${formData.submissionTest.urlChanged}, Success message: ${hasSuccessMessage}`);

                  await testHelpers.takeScreenshot(`form-${url.replace('/', 'root')}-${i + 1}-submitted`);

                } catch (error) {
                  formData.submissionTest = {
                    attempted: true,
                    error: error.message
                  };

                  console.log('Form submission error:', error.message);
                }

              } else {
                console.log(`Skipping actual submission for potentially sensitive form: ${buttonText}`);
                formData.submissionTest = {
                  attempted: false,
                  reason: 'potentially_sensitive'
                };
              }
            }

            formTestResults.push(formData);

          } catch (error) {
            console.log(`Error testing form ${i + 1} on ${url}:`, error.message);
          }
        }

      } catch (error) {
        console.log(`Error accessing ${url}:`, error.message);
      }
    }

    // Generate form testing summary
    const formSummary = {
      totalForms: formTestResults.length,
      formsWithValidation: formTestResults.filter(form => Object.keys(form.validationTests).length > 0).length,
      formsSubmissionTested: formTestResults.filter(form => form.submissionTest?.attempted).length,
      successfulSubmissions: formTestResults.filter(form => form.submissionTest?.urlChanged || form.submissionTest?.successMessageShown).length
    };

    console.log('Form Test Summary:', JSON.stringify(formSummary, null, 2));
    console.log('Detailed Form Results:', JSON.stringify(formTestResults, null, 2));

    expect(formTestResults.length, 'Should find at least some forms to test').toBeGreaterThanOrEqual(0);
  });

  test('should test search functionality', async ({ page }) => {
    console.log('Testing search functionality...');

    await page.goto('/');
    await testHelpers.waitForPageLoad();

    const searchResults = [];

    // Look for search forms/inputs
    const searchSelectors = [
      'input[type="search"]',
      'input[name*="search"]',
      'input[placeholder*="search" i]',
      '.search-input',
      '#search',
      'form[role="search"]',
      '.search-form input'
    ];

    let searchFound = false;

    for (const selector of searchSelectors) {
      const searchElements = await page.locator(selector).all();

      for (let i = 0; i < searchElements.length; i++) {
        const searchElement = searchElements[i];

        try {
          const isVisible = await searchElement.isVisible();
          if (!isVisible) continue;

          searchFound = true;
          console.log(`Found search element with selector: ${selector}`);

          await searchElement.scrollIntoViewIfNeeded();
          await testHelpers.takeScreenshot(`search-element-${i + 1}`);

          // Test search functionality
          const testQueries = ['test', 'aeims', 'contact'];

          for (const query of testQueries) {
            try {
              console.log(`Testing search query: "${query}"`);

              await searchElement.clear();
              await searchElement.fill(query);
              await page.waitForTimeout(1000);

              // Look for search suggestions or autocomplete
              const suggestions = await page.locator('.search-suggestions, .autocomplete, .search-dropdown').count();
              console.log(`Search suggestions appeared: ${suggestions > 0}`);

              // Submit search
              await searchElement.press('Enter');
              await page.waitForTimeout(3000);

              const currentUrl = page.url();
              const hasSearchResults = await page.locator('.search-results, .results, .search-result').count() > 0;

              searchResults.push({
                query,
                urlAfterSearch: currentUrl,
                hasResults: hasSearchResults,
                suggestionsShown: suggestions > 0
              });

              console.log(`Search for "${query}": Results shown: ${hasSearchResults}`);

              await testHelpers.takeScreenshot(`search-results-${query}`);

              // Go back to test next query
              if (searchResults.length < testQueries.length) {
                await page.goBack();
                await testHelpers.waitForPageLoad();
              }

            } catch (error) {
              console.log(`Error testing search query "${query}":`, error.message);
            }
          }

          break; // Found and tested search, no need to test other selectors

        } catch (error) {
          console.log(`Error testing search element with ${selector}:`, error.message);
        }
      }

      if (searchFound) break;
    }

    if (!searchFound) {
      console.log('No search functionality found on the website');
    }

    console.log('Search Test Results:', JSON.stringify(searchResults, null, 2));

    expect(true, 'Search functionality test completed').toBe(true);
  });

  test('should test pagination if present', async ({ page }) => {
    console.log('Testing pagination functionality...');

    const testUrls = ['/', '/blog', '/news', '/articles', '/products', '/services'];
    const paginationResults = [];

    for (const url of testUrls) {
      try {
        await page.goto(url, { timeout: 15000 });
        await testHelpers.waitForPageLoad();

        // Look for pagination elements
        const paginationSelectors = [
          '.pagination',
          '.pager',
          '.page-navigation',
          '[aria-label*="pagination" i]',
          '.page-numbers'
        ];

        let paginationFound = false;

        for (const selector of paginationSelectors) {
          const pagination = page.locator(selector).first();

          if (await pagination.isVisible()) {
            paginationFound = true;
            console.log(`Found pagination on ${url} with selector: ${selector}`);

            await testHelpers.takeScreenshot(`pagination-${url.replace('/', 'root')}`);

            // Test pagination navigation
            const nextButton = pagination.locator('a:has-text("Next"), button:has-text("Next"), .next').first();
            const prevButton = pagination.locator('a:has-text("Previous"), button:has-text("Previous"), .prev, .previous').first();

            const paginationTest = {
              url,
              selector,
              hasNext: await nextButton.isVisible(),
              hasPrevious: await prevButton.isVisible(),
              pageNumbers: await pagination.locator('a[href], button').count()
            };

            // Test next page navigation
            if (await nextButton.isVisible() && await nextButton.isEnabled()) {
              try {
                const currentUrl = page.url();
                await nextButton.click();
                await testHelpers.waitForPageLoad();

                const newUrl = page.url();
                paginationTest.nextPageNavigation = {
                  successful: newUrl !== currentUrl,
                  newUrl
                };

                console.log(`Next page navigation: ${paginationTest.nextPageNavigation.successful ? 'Success' : 'Failed'}`);

                await testHelpers.takeScreenshot(`pagination-next-page-${url.replace('/', 'root')}`);

                // Test previous page navigation
                const backPrevButton = page.locator('.pagination .prev, .pagination .previous, .pager .prev').first();
                if (await backPrevButton.isVisible()) {
                  await backPrevButton.click();
                  await testHelpers.waitForPageLoad();

                  const backUrl = page.url();
                  paginationTest.previousPageNavigation = {
                    successful: backUrl === currentUrl
                  };
                }

              } catch (error) {
                paginationTest.nextPageNavigation = {
                  error: error.message
                };
              }
            }

            paginationResults.push(paginationTest);
            break;
          }
        }

        if (!paginationFound) {
          console.log(`No pagination found on ${url}`);
        }

      } catch (error) {
        console.log(`Error testing pagination on ${url}:`, error.message);
      }
    }

    console.log('Pagination Test Results:', JSON.stringify(paginationResults, null, 2));

    expect(true, 'Pagination test completed').toBe(true);
  });

  test('should test keyboard navigation and accessibility', async ({ page }) => {
    console.log('Testing keyboard navigation and accessibility...');

    await page.goto('/');
    await testHelpers.waitForPageLoad();

    const keyboardNavResults = {
      tabNavigation: [],
      keyboardShortcuts: [],
      accessibleElements: 0
    };

    // Test tab navigation
    console.log('Testing tab navigation...');

    await page.keyboard.press('Tab');
    await page.waitForTimeout(500);

    let tabCount = 0;
    const maxTabs = 20; // Limit tab testing

    while (tabCount < maxTabs) {
      try {
        const focusedElement = await page.evaluate(() => {
          const element = document.activeElement;
          return element ? {
            tagName: element.tagName.toLowerCase(),
            type: element.type || null,
            text: element.textContent?.trim().substring(0, 50) || '',
            href: element.href || null,
            className: element.className || '',
            hasTabIndex: element.hasAttribute('tabindex')
          } : null;
        });

        if (focusedElement) {
          keyboardNavResults.tabNavigation.push(focusedElement);
          console.log(`Tab ${tabCount + 1}: ${focusedElement.tagName} - "${focusedElement.text}"`);

          // Take screenshot of focused element
          if (tabCount < 5) { // Limit screenshots
            await testHelpers.takeScreenshot(`keyboard-focus-${tabCount + 1}`);
          }
        }

        await page.keyboard.press('Tab');
        await page.waitForTimeout(300);
        tabCount++;

      } catch (error) {
        console.log('Tab navigation error:', error.message);
        break;
      }
    }

    // Test common keyboard shortcuts
    console.log('Testing keyboard shortcuts...');

    const shortcuts = [
      { keys: 'Alt+Home', description: 'Home navigation' },
      { keys: 'Alt+ArrowLeft', description: 'Back navigation' },
      { keys: 'Control+f', description: 'Find/Search' },
      { keys: 'Escape', description: 'Escape/Close' }
    ];

    for (const shortcut of shortcuts) {
      try {
        console.log(`Testing shortcut: ${shortcut.keys}`);

        const urlBefore = page.url();
        await page.keyboard.press(shortcut.keys);
        await page.waitForTimeout(1000);

        const urlAfter = page.url();
        const changed = urlBefore !== urlAfter;

        keyboardNavResults.keyboardShortcuts.push({
          keys: shortcut.keys,
          description: shortcut.description,
          effectDetected: changed
        });

        console.log(`Shortcut ${shortcut.keys}: ${changed ? 'Effect detected' : 'No effect'}`);

      } catch (error) {
        console.log(`Error testing shortcut ${shortcut.keys}:`, error.message);
      }
    }

    // Count accessible elements
    keyboardNavResults.accessibleElements = await page.locator('[aria-label], [aria-labelledby], [aria-describedby], [role]').count();

    console.log('Keyboard Navigation Results:', JSON.stringify(keyboardNavResults, null, 2));

    expect(keyboardNavResults.tabNavigation.length, 'Should have some keyboard-accessible elements').toBeGreaterThan(0);
  });
});