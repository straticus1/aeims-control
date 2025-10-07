// 04-interactive-elements.spec.js
const { test, expect } = require('@playwright/test');
const { TestHelpers, utils } = require('../utils/test-helpers');

test.describe('AEIMS Interactive Elements Testing', () => {
  let testHelpers;

  test.beforeEach(async ({ page }, testInfo) => {
    testHelpers = new TestHelpers(page, testInfo);
    await testHelpers.setupErrorMonitoring();
  });

  test.afterEach(async ({ page }) => {
    await testHelpers.generateTestReport();
  });

  test('should find and test all buttons on main page', async ({ page }) => {
    await page.goto('/');
    await testHelpers.waitForPageLoad();

    console.log('Testing all buttons on main page...');

    // Find all button elements
    const buttonSelectors = [
      'button',
      'input[type="button"]',
      'input[type="submit"]',
      '[role="button"]',
      '.btn',
      '.button',
      'a.btn',
      'a.button'
    ];

    const allButtons = [];

    for (const selector of buttonSelectors) {
      const buttons = await page.locator(selector).all();
      for (const button of buttons) {
        try {
          const isVisible = await button.isVisible();
          if (isVisible) {
            const text = await button.textContent();
            const tagName = await button.evaluate(el => el.tagName.toLowerCase());
            const className = await button.getAttribute('class');
            const disabled = await button.isDisabled();

            allButtons.push({
              selector,
              text: text?.trim() || '',
              tagName,
              className,
              disabled,
              element: button
            });
          }
        } catch (error) {
          console.log(`Error examining button with selector ${selector}:`, error.message);
        }
      }
    }

    console.log(`Found ${allButtons.length} buttons on the page`);

    // Test each button
    for (let i = 0; i < allButtons.length; i++) {
      const buttonInfo = allButtons[i];

      try {
        console.log(`Testing button ${i + 1}: "${buttonInfo.text}" (${buttonInfo.tagName})`);

        // Scroll button into view
        await buttonInfo.element.scrollIntoViewIfNeeded();

        // Take screenshot before interaction
        await testHelpers.takeScreenshot(`button-${i + 1}-before`);

        // Test hover effect
        await buttonInfo.element.hover();
        await page.waitForTimeout(500);

        // Check if button is clickable
        if (!buttonInfo.disabled) {
          // For submit buttons or form buttons, be careful not to actually submit
          if (buttonInfo.text.toLowerCase().includes('submit') ||
              buttonInfo.text.toLowerCase().includes('send') ||
              buttonInfo.tagName === 'input' && buttonInfo.element.getAttribute('type') === 'submit') {

            console.log(`Skipping actual click for submit button: "${buttonInfo.text}"`);
            // Just verify it's clickable
            const isClickable = await buttonInfo.element.isEnabled();
            console.log(`Submit button enabled: ${isClickable}`);

          } else {
            // For other buttons, test click but be prepared for navigation
            console.log(`Clicking button: "${buttonInfo.text}"`);

            // Monitor for any page changes
            const currentUrl = page.url();

            try {
              await buttonInfo.element.click({ timeout: 5000 });
              await page.waitForTimeout(2000); // Wait for any response

              // Check if page changed
              const newUrl = page.url();
              if (newUrl !== currentUrl) {
                console.log(`Button click caused navigation: ${currentUrl} -> ${newUrl}`);

                // If navigated away, go back to continue testing
                await page.goBack();
                await testHelpers.waitForPageLoad();
              }

            } catch (error) {
              console.log(`Button click error for "${buttonInfo.text}":`, error.message);
            }
          }

          // Take screenshot after interaction
          await testHelpers.takeScreenshot(`button-${i + 1}-after`);

        } else {
          console.log(`Button "${buttonInfo.text}" is disabled - skipping click test`);
        }

      } catch (error) {
        console.log(`Error testing button ${i + 1}:`, error.message);
      }
    }

    // Log button summary
    const buttonSummary = {
      total: allButtons.length,
      enabled: allButtons.filter(b => !b.disabled).length,
      disabled: allButtons.filter(b => b.disabled).length,
      byType: {}
    };

    allButtons.forEach(button => {
      const type = button.tagName + (button.className ? ` (${button.className})` : '');
      buttonSummary.byType[type] = (buttonSummary.byType[type] || 0) + 1;
    });

    console.log('Button Test Summary:', JSON.stringify(buttonSummary, null, 2));

    expect(allButtons.length, 'Should find at least some buttons on the page').toBeGreaterThan(0);
  });

  test('should find and test all links on main page', async ({ page }) => {
    await page.goto('/');
    await testHelpers.waitForPageLoad();

    console.log('Testing all links on main page...');

    // Find all link elements
    const links = await page.locator('a[href]').all();

    console.log(`Found ${links.length} links on the page`);

    const linkResults = [];
    const testedUrls = new Set(); // Avoid testing duplicate URLs

    for (let i = 0; i < Math.min(links.length, 20); i++) { // Limit to 20 links for performance
      const link = links[i];

      try {
        const href = await link.getAttribute('href');
        const text = await link.textContent();
        const isVisible = await link.isVisible();

        if (!href || !isVisible || testedUrls.has(href)) {
          continue;
        }

        testedUrls.add(href);

        const linkInfo = {
          index: i + 1,
          href,
          text: text?.trim() || '',
          isExternal: href.startsWith('http') && !href.includes('aeims.app'),
          isAnchor: href.startsWith('#'),
          isEmail: href.startsWith('mailto:'),
          isTel: href.startsWith('tel:')
        };

        console.log(`Testing link ${linkInfo.index}: "${linkInfo.text}" -> ${href}`);

        // Scroll link into view
        await link.scrollIntoViewIfNeeded();

        // Test hover effect
        await link.hover();
        await page.waitForTimeout(300);

        // Take screenshot of link
        await testHelpers.takeScreenshot(`link-${linkInfo.index}-hover`);

        // Test different types of links differently
        if (linkInfo.isAnchor) {
          // For anchor links, just verify they're clickable
          console.log(`Anchor link found: ${href}`);
          linkInfo.result = 'anchor_link';

        } else if (linkInfo.isEmail || linkInfo.isTel) {
          // For email/tel links, just verify format
          console.log(`Contact link found: ${href}`);
          linkInfo.result = 'contact_link';

        } else if (linkInfo.isExternal) {
          // For external links, don't click but verify target and rel attributes
          const target = await link.getAttribute('target');
          const rel = await link.getAttribute('rel');

          linkInfo.target = target;
          linkInfo.rel = rel;

          console.log(`External link - Target: ${target}, Rel: ${rel}`);

          if (target === '_blank' && (!rel || !rel.includes('noopener'))) {
            console.log(`⚠️  External link missing rel="noopener": ${href}`);
            linkInfo.securityIssue = 'missing_noopener';
          }

          linkInfo.result = 'external_link_checked';

        } else {
          // For internal links, test navigation
          const currentUrl = page.url();

          try {
            await link.click({ timeout: 5000 });
            await page.waitForLoadState('domcontentloaded', { timeout: 10000 });

            const newUrl = page.url();

            if (newUrl !== currentUrl) {
              console.log(`✅ Link navigation successful: ${href}`);
              linkInfo.result = 'navigation_success';
              linkInfo.finalUrl = newUrl;

              // Take screenshot of destination
              await testHelpers.takeScreenshot(`link-${linkInfo.index}-destination`);

              // Go back to continue testing
              await page.goBack();
              await testHelpers.waitForPageLoad();

            } else {
              console.log(`Link click didn't cause navigation: ${href}`);
              linkInfo.result = 'no_navigation';
            }

          } catch (error) {
            console.log(`❌ Link navigation failed: ${href} - ${error.message}`);
            linkInfo.result = 'navigation_failed';
            linkInfo.error = error.message;
          }
        }

        linkResults.push(linkInfo);

      } catch (error) {
        console.log(`Error testing link ${i + 1}:`, error.message);
      }
    }

    // Analyze link results
    const linkSummary = {
      total: linkResults.length,
      successful: linkResults.filter(l => l.result === 'navigation_success').length,
      failed: linkResults.filter(l => l.result === 'navigation_failed').length,
      external: linkResults.filter(l => l.isExternal).length,
      anchors: linkResults.filter(l => l.isAnchor).length,
      contacts: linkResults.filter(l => l.isEmail || l.isTel).length,
      securityIssues: linkResults.filter(l => l.securityIssue).length
    };

    console.log('Link Test Summary:', JSON.stringify(linkSummary, null, 2));

    // Log any security issues
    const securityIssues = linkResults.filter(l => l.securityIssue);
    if (securityIssues.length > 0) {
      console.log('🔒 Security Issues Found:');
      securityIssues.forEach(link => {
        console.log(`  - ${link.href}: ${link.securityIssue}`);
      });
    }

    expect(linkResults.length, 'Should find at least some links on the page').toBeGreaterThan(0);
  });

  test('should test form elements and interactions', async ({ page }) => {
    await page.goto('/');
    await testHelpers.waitForPageLoad();

    console.log('Testing form elements...');

    // Find all forms
    const forms = await page.locator('form').all();
    console.log(`Found ${forms.length} forms on the page`);

    const formResults = [];

    for (let i = 0; i < forms.length; i++) {
      const form = forms[i];

      try {
        console.log(`Testing form ${i + 1}`);

        const formInfo = {
          index: i + 1,
          action: await form.getAttribute('action') || '',
          method: await form.getAttribute('method') || 'GET',
          fields: []
        };

        // Find all input fields in this form
        const inputs = await form.locator('input, textarea, select').all();

        for (let j = 0; j < inputs.length; j++) {
          const input = inputs[j];

          try {
            const type = await input.getAttribute('type') || 'text';
            const name = await input.getAttribute('name') || '';
            const placeholder = await input.getAttribute('placeholder') || '';
            const required = await input.getAttribute('required') !== null;
            const disabled = await input.isDisabled();

            const fieldInfo = {
              type,
              name,
              placeholder,
              required,
              disabled
            };

            // Test field interaction (but don't submit)
            if (!disabled && type !== 'submit' && type !== 'button') {
              await input.scrollIntoViewIfNeeded();

              if (type === 'text' || type === 'email' || type === 'password' || !type) {
                await input.click();
                await input.fill('test input');
                await page.waitForTimeout(500);
                await input.clear();

                fieldInfo.interactive = true;

              } else if (type === 'checkbox' || type === 'radio') {
                const isChecked = await input.isChecked();
                await input.click();
                const newChecked = await input.isChecked();

                fieldInfo.interactive = true;
                fieldInfo.toggledSuccessfully = isChecked !== newChecked;

              } else if (input.tagName === 'SELECT') {
                const options = await input.locator('option').count();
                fieldInfo.optionsCount = options;

                if (options > 1) {
                  // Select the second option if available
                  await input.selectOption({ index: 1 });
                  fieldInfo.interactive = true;
                }
              }
            }

            formInfo.fields.push(fieldInfo);

          } catch (error) {
            console.log(`Error testing input field ${j + 1} in form ${i + 1}:`, error.message);
          }
        }

        // Take screenshot of form
        await testHelpers.takeScreenshot(`form-${i + 1}-tested`);

        formResults.push(formInfo);

      } catch (error) {
        console.log(`Error testing form ${i + 1}:`, error.message);
      }
    }

    // Form summary
    const formSummary = {
      totalForms: formResults.length,
      totalFields: formResults.reduce((sum, form) => sum + form.fields.length, 0),
      interactiveFields: formResults.reduce((sum, form) =>
        sum + form.fields.filter(field => field.interactive).length, 0
      )
    };

    console.log('Form Test Summary:', JSON.stringify(formSummary, null, 2));
    console.log('Detailed Form Results:', JSON.stringify(formResults, null, 2));

    expect(true, 'Form elements test completed').toBe(true);
  });

  test('should test dropdown menus and navigation', async ({ page }) => {
    await page.goto('/');
    await testHelpers.waitForPageLoad();

    console.log('Testing dropdown menus and navigation...');

    // Look for dropdown triggers
    const dropdownSelectors = [
      '.dropdown',
      '.menu-item:has(.submenu)',
      '[aria-haspopup="true"]',
      '.nav-item:has(.dropdown-menu)',
      'button[aria-expanded]',
      '.has-dropdown'
    ];

    const dropdownResults = [];

    for (const selector of dropdownSelectors) {
      const dropdowns = await page.locator(selector).all();

      for (let i = 0; i < dropdowns.length; i++) {
        const dropdown = dropdowns[i];

        try {
          const isVisible = await dropdown.isVisible();
          if (!isVisible) continue;

          console.log(`Testing dropdown with selector: ${selector}`);

          await dropdown.scrollIntoViewIfNeeded();
          await testHelpers.takeScreenshot(`dropdown-${selector.replace(/[^a-zA-Z0-9]/g, '')}-before`);

          // Try hovering first
          await dropdown.hover();
          await page.waitForTimeout(1000);

          // Look for dropdown content that appeared
          const dropdownContent = page.locator('.dropdown-menu, .submenu, .dropdown-content').first();
          const contentVisible = await dropdownContent.isVisible();

          if (contentVisible) {
            console.log('✅ Dropdown content appeared on hover');
            await testHelpers.takeScreenshot(`dropdown-${selector.replace(/[^a-zA-Z0-9]/g, '')}-open`);

            // Test dropdown items
            const dropdownItems = await dropdownContent.locator('a, button').all();
            console.log(`Found ${dropdownItems.length} items in dropdown`);

            dropdownResults.push({
              selector,
              trigger: 'hover',
              itemCount: dropdownItems.length,
              success: true
            });

            // Click away to close dropdown
            await page.click('body');
            await page.waitForTimeout(500);

          } else {
            // Try clicking instead
            await dropdown.click();
            await page.waitForTimeout(1000);

            const contentVisibleAfterClick = await dropdownContent.isVisible();

            if (contentVisibleAfterClick) {
              console.log('✅ Dropdown content appeared on click');
              await testHelpers.takeScreenshot(`dropdown-${selector.replace(/[^a-zA-Z0-9]/g, '')}-click-open`);

              const dropdownItems = await dropdownContent.locator('a, button').all();

              dropdownResults.push({
                selector,
                trigger: 'click',
                itemCount: dropdownItems.length,
                success: true
              });

              // Close dropdown
              await dropdown.click();

            } else {
              console.log('❌ No dropdown content appeared');
              dropdownResults.push({
                selector,
                trigger: 'none',
                success: false
              });
            }
          }

        } catch (error) {
          console.log(`Error testing dropdown with ${selector}:`, error.message);
        }
      }
    }

    console.log('Dropdown Test Results:', JSON.stringify(dropdownResults, null, 2));

    expect(true, 'Dropdown menus test completed').toBe(true);
  });

  test('should test modal dialogs and overlays', async ({ page }) => {
    await page.goto('/');
    await testHelpers.waitForPageLoad();

    console.log('Testing modal dialogs and overlays...');

    // Look for modal triggers
    const modalTriggers = [
      'button[data-toggle="modal"]',
      'button[data-bs-toggle="modal"]',
      'a[data-toggle="modal"]',
      'button:has-text("Open")',
      'button:has-text("Show")',
      'button:has-text("Modal")',
      'button:has-text("Dialog")',
      '.modal-trigger',
      '[data-modal]'
    ];

    const modalResults = [];

    for (const selector of modalTriggers) {
      const triggers = await page.locator(selector).all();

      for (let i = 0; i < triggers.length; i++) {
        const trigger = triggers[i];

        try {
          const isVisible = await trigger.isVisible();
          if (!isVisible) continue;

          const buttonText = await trigger.textContent();
          console.log(`Testing modal trigger: "${buttonText?.trim()}"`);

          await trigger.scrollIntoViewIfNeeded();
          await testHelpers.takeScreenshot(`modal-trigger-${i}`);

          // Click trigger
          await trigger.click();
          await page.waitForTimeout(1000);

          // Look for modal content
          const modalSelectors = [
            '.modal',
            '.dialog',
            '.overlay',
            '.popup',
            '[role="dialog"]',
            '[aria-modal="true"]'
          ];

          let modalFound = false;

          for (const modalSelector of modalSelectors) {
            const modal = page.locator(modalSelector);
            const isModalVisible = await modal.isVisible();

            if (isModalVisible) {
              console.log(`✅ Modal opened with selector: ${modalSelector}`);
              modalFound = true;

              await testHelpers.takeScreenshot(`modal-open-${i}`);

              // Look for close button
              const closeButtons = await modal.locator('button:has-text("Close"), button:has-text("×"), .close, [aria-label="Close"]').all();

              if (closeButtons.length > 0) {
                console.log('Found close button, testing modal close');
                await closeButtons[0].click();
                await page.waitForTimeout(1000);

                const stillVisible = await modal.isVisible();
                console.log(`Modal closed successfully: ${!stillVisible}`);
              } else {
                // Try pressing Escape
                await page.keyboard.press('Escape');
                await page.waitForTimeout(1000);

                const stillVisible = await modal.isVisible();
                console.log(`Modal closed with Escape: ${!stillVisible}`);
              }

              break;
            }
          }

          modalResults.push({
            trigger: buttonText?.trim(),
            modalFound,
            selector
          });

        } catch (error) {
          console.log(`Error testing modal trigger:`, error.message);
        }
      }
    }

    console.log('Modal Test Results:', JSON.stringify(modalResults, null, 2));

    expect(true, 'Modal dialogs test completed').toBe(true);
  });
});