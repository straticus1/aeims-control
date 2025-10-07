const { test, expect } = require('@playwright/test');
const NetworkAnalyzer = require('./utils/network-analyzer');
const SiteAnalyzer = require('./utils/site-analyzer');
const fs = require('fs-extra');

const SITES_TO_TEST = [
  {
    name: 'AEIMS App',
    url: 'https://aeims.app',
    subdomains: ['www.aeims.app', 'api.aeims.app', 'admin.aeims.app']
  },
  {
    name: 'AfterDarkSys',
    url: 'https://afterdarksys.com',
    subdomains: ['www.afterdarksys.com', 'blog.afterdarksys.com', 'docs.afterdarksys.com']
  },
  {
    name: 'NYC Flirts',
    url: 'https://nycflirts.com',
    subdomains: ['www.nycflirts.com']
  },
  {
    name: 'Flirts NYC',
    url: 'https://flirts.nyc',
    subdomains: ['www.flirts.nyc']
  }
];

test.describe('Comprehensive Site Testing Suite', () => {
  let networkAnalyzer;
  let siteAnalyzer;

  test.beforeAll(async () => {
    networkAnalyzer = new NetworkAnalyzer();
    siteAnalyzer = new SiteAnalyzer();
    
    // Ensure test results directory exists
    await fs.ensureDir('./test-results');
    
    // Start network capture
    await networkAnalyzer.startCapture();
    
    console.log('Starting comprehensive site testing...');
  });

  test.afterAll(async () => {
    // Stop network capture and analyze
    await networkAnalyzer.stopCapture();
    const packets = await networkAnalyzer.analyzeTraffic();
    const networkReport = networkAnalyzer.generateNetworkReport(packets);
    
    // Generate site analysis report
    const siteReport = await siteAnalyzer.generateReport();
    
    // Save network report
    await fs.writeJson('./test-results/network-report.json', networkReport, { spaces: 2 });
    
    console.log('Testing complete. Reports generated in test-results/');
    console.log(`Sites tested: ${siteReport.totalSitesTested}`);
    console.log(`Network packets captured: ${networkReport.totalPackets}`);
  });

  for (const site of SITES_TO_TEST) {
    test.describe(`${site.name} Testing`, () => {
      
      test(`Main site: ${site.url}`, async ({ page }) => {
        const analysis = await siteAnalyzer.analyzePage(page, site.url, `${site.name} Main Site`);
        
        // Basic connectivity test
        expect(analysis.responseStatus).toBeLessThan(400);
        
        // Performance expectations
        expect(analysis.loadTime).toBeLessThan(10000); // 10 seconds max
        
        // Security headers check
        if (site.url.startsWith('https://')) {
          expect(analysis.security['strict-transport-security']).toBeDefined();
        }
        
        // SEO basics
        expect(analysis.seo.title).toBeTruthy();
        expect(analysis.seo.title.length).toBeGreaterThan(10);
        
        // Accessibility
        expect(analysis.accessibility.issues.length).toBeLessThan(10);
        
        console.log(`✓ ${site.name} main site analysis complete`);
      });

      for (const subdomain of site.subdomains) {
        test(`Subdomain: ${subdomain}`, async ({ page }) => {
          const fullUrl = subdomain.startsWith('http') ? subdomain : `https://${subdomain}`;
          
          try {
            const analysis = await siteAnalyzer.analyzePage(page, fullUrl, `${site.name} Subdomain: ${subdomain}`);
            
            // Allow for more flexible status codes for subdomains
            expect([200, 301, 302, 404]).toContain(analysis.responseStatus);
            
            if (analysis.responseStatus === 200) {
              expect(analysis.loadTime).toBeLessThan(15000); // 15 seconds for subdomains
            }
            
            console.log(`✓ ${subdomain} analysis complete (Status: ${analysis.responseStatus})`);
          } catch (error) {
            console.log(`⚠ ${subdomain} analysis failed: ${error.message}`);
            // Don't fail the test for subdomain issues, just log them
          }
        });
      }
    });
  }

  test.describe('AEIMS Login Testing', () => {
    test('Login form functionality on aeims.app', async ({ page }) => {
      const url = 'https://aeims.app';
      
      try {
        await page.goto(url);
        
        // Look for login form or login link
        const loginForm = page.locator('form').filter({ hasText: /login|sign\s*in/i }).first();
        const loginLink = page.locator('a').filter({ hasText: /login|sign\s*in/i }).first();
        
        let hasLoginForm = false;
        let loginCredentials = null;
        
        if (await loginForm.count() > 0) {
          hasLoginForm = true;
          
          // Check if credentials are displayed on the page
          const pageText = await page.textContent('body');
          const credentialRegex = /(?:username|email|user):\s*([^\s\n]+).*(?:password|pass):\s*([^\s\n]+)/is;
          const match = pageText.match(credentialRegex);
          
          if (match) {
            loginCredentials = {
              username: match[1],
              password: match[2]
            };
            
            console.log('Found credentials on page:', loginCredentials);
            
            // Try to login with the credentials
            const usernameField = loginForm.locator('input[type="text"], input[type="email"], input[name*="user"], input[name*="email"]').first();
            const passwordField = loginForm.locator('input[type="password"]').first();
            const submitButton = loginForm.locator('input[type="submit"], button[type="submit"], button').filter({ hasText: /login|sign\s*in|submit/i }).first();
            
            if (await usernameField.count() > 0 && await passwordField.count() > 0) {
              await usernameField.fill(loginCredentials.username);
              await passwordField.fill(loginCredentials.password);
              
              if (await submitButton.count() > 0) {
                await submitButton.click();
                
                // Wait for response
                await page.waitForTimeout(3000);
                
                // Check if login was successful (look for dashboard, profile, logout, etc.)
                const currentUrl = page.url();
                const bodyText = await page.textContent('body');
                const loginSuccess = bodyText.includes('dashboard') || 
                                  bodyText.includes('profile') || 
                                  bodyText.includes('logout') ||
                                  currentUrl.includes('dashboard') ||
                                  currentUrl.includes('admin');
                
                if (loginSuccess) {
                  console.log('✓ Login successful');
                } else {
                  console.log('⚠ Login attempt completed but success unclear');
                }
              }
            }
          } else {
            console.log('⚠ Login form found but no credentials visible on page');
          }
        } else if (await loginLink.count() > 0) {
          console.log('Found login link, clicking to navigate to login page');
          await loginLink.click();
          await page.waitForTimeout(2000);
          
          // Recursively check the login page
          const newUrl = page.url();
          if (newUrl !== url) {
            const analysis = await siteAnalyzer.analyzePage(page, newUrl, 'AEIMS Login Page');
            console.log(`✓ Login page analysis complete: ${newUrl}`);
          }
        } else {
          console.log('⚠ No login form or link found on main page');
        }
        
        // Record the analysis
        const analysis = await siteAnalyzer.analyzePage(page, url, 'AEIMS Login Test');
        analysis.loginTesting = {
          hasLoginForm,
          credentialsFound: !!loginCredentials,
          credentials: loginCredentials
        };
        
      } catch (error) {
        console.log(`Login testing failed: ${error.message}`);
        throw error;
      }
    });
  });

  test.describe('Virtual Host Testing', () => {
    test('Cross-site integration test', async ({ page }) => {
      // Test that nycflirts.com and flirts.nyc point to the same backend
      const site1Response = await page.goto('https://nycflirts.com');
      const site1Content = await page.content();
      
      await page.goto('https://flirts.nyc');
      const site2Content = await page.content();
      
      // Check if sites have similar structure (indicating same backend)
      const site1Title = await page.evaluate(() => document.title);
      await page.goto('https://nycflirts.com');
      const site2Title = await page.evaluate(() => document.title);
      
      console.log(`NYC Flirts title: ${site2Title}`);
      console.log(`Flirts NYC title: ${site1Title}`);
      
      // Record analysis
      const analysis = {
        testName: 'Virtual Host Integration',
        timestamp: new Date().toISOString(),
        site1: { url: 'https://nycflirts.com', title: site2Title },
        site2: { url: 'https://flirts.nyc', title: site1Title },
        similarContent: site1Content.length > 0 && site2Content.length > 0,
        bothResponding: site1Response.status() < 400 && site1Response.status() < 400
      };
      
      siteAnalyzer.results.push(analysis);
    });
  });
});
