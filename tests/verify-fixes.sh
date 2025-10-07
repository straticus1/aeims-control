#!/bin/bash

# AEIMS Website Fix Verification Script
# Run this script to quickly verify if the server issues have been resolved

echo "🔍 AEIMS Website Fix Verification"
echo "=================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check HTTP status
check_url() {
    local url=$1
    local name=$2

    echo -n "Checking $name ($url)... "

    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null)

    if [ "$status" = "200" ]; then
        echo -e "${GREEN}✅ OK (HTTP $status)${NC}"
        return 0
    elif [ "$status" = "000" ]; then
        echo -e "${RED}❌ FAILED (No response)${NC}"
        return 1
    else
        echo -e "${YELLOW}⚠️  WARNING (HTTP $status)${NC}"
        return 1
    fi
}

# Function to check for login functionality
check_login() {
    local base_url=$1
    local name=$2

    echo -n "Checking $name login functionality... "

    # Check common login paths
    login_paths=("/login" "/signin" "/auth")
    login_found=false

    for path in "${login_paths[@]}"; do
        status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${base_url}${path}" 2>/dev/null)
        if [ "$status" = "200" ]; then
            echo -e "${GREEN}✅ FOUND at ${path}${NC}"
            login_found=true
            break
        fi
    done

    if [ "$login_found" = false ]; then
        echo -e "${RED}❌ NOT FOUND${NC}"
        return 1
    fi

    return 0
}

# Function to run quick Playwright test
run_quick_test() {
    echo ""
    echo "🧪 Running Quick Automated Tests..."
    echo "===================================="

    if [ -f "package.json" ]; then
        echo "Running Playwright quick check..."
        npx playwright test tests/00-quick-check.spec.js --project="Desktop Chrome" --reporter=list
    else
        echo "❌ Playwright tests not available in current directory"
        echo "   Navigate to the tests directory and run: npx playwright test tests/00-quick-check.spec.js"
    fi
}

# Main checks
echo "📋 Step 1: Basic Connectivity Check"
echo "-----------------------------------"

failed=0

check_url "https://www.aeims.app" "Main Website" || ((failed++))
check_url "https://aeims.app" "Root Domain" || ((failed++))
check_url "https://api.aeims.app" "API Subdomain" || ((failed++))
check_url "https://admin.aeims.app" "Admin Subdomain" || ((failed++))

echo ""
echo "📋 Step 2: Login Functionality Check"
echo "------------------------------------"

check_login "https://www.aeims.app" "Main Website" || ((failed++))
check_login "https://admin.aeims.app" "Admin Portal" || ((failed++))

echo ""
echo "📋 Step 3: Security Headers Check"
echo "---------------------------------"

echo -n "Checking security headers... "
headers=$(curl -s -I "https://www.aeims.app" 2>/dev/null | grep -i "strict-transport-security\|x-frame-options\|x-content-type-options\|x-xss-protection" | wc -l)

if [ "$headers" -gt 0 ]; then
    echo -e "${GREEN}✅ $headers security headers found${NC}"
else
    echo -e "${YELLOW}⚠️  No security headers detected${NC}"
    ((failed++))
fi

# Summary
echo ""
echo "📊 Summary"
echo "=========="

if [ $failed -eq 0 ]; then
    echo -e "${GREEN}🎉 All checks passed! Website appears to be fixed.${NC}"
    echo ""
    echo "✅ Next steps:"
    echo "   1. Run full test suite: npx playwright test"
    echo "   2. Test login functionality manually"
    echo "   3. Verify all interactive elements work"
    run_quick_test
else
    echo -e "${RED}❌ $failed issues found. Website still needs attention.${NC}"
    echo ""
    echo "🔧 Issues to resolve:"
    [ $failed -gt 3 ] && echo "   - Fix server errors (502/504)"
    echo "   - Implement login functionality"
    echo "   - Add security headers"
    echo "   - Test full functionality"
fi

echo ""
echo "📚 For detailed testing, run:"
echo "   cd /path/to/tests && npx playwright test --ui"
echo ""
echo "📄 Full test report available at:"
echo "   ./TESTING_RESULTS_SUMMARY.md"