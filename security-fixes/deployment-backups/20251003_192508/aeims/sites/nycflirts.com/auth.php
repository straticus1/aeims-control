<?php
/**
 * Customer Authentication System
 * Handles login, signup, and logout for customer sites
 */

session_start();

// Load site configuration, customer manager, and SSO
require_once '../../services/SiteManager.php';
require_once '../../services/CustomerManager.php';
require_once '../../services/SSOManager.php';

try {
    $siteManager = new \AEIMS\Services\SiteManager();
    $customerManager = new \AEIMS\Services\CustomerManager();
    $ssoManager = new \AEIMS\Services\SSOManager();

    $site = $siteManager->getSite('flirts.nyc');
    if (!$site || !$site['active']) {
        http_response_code(503);
        die('Site temporarily unavailable');
    }
} catch (Exception $e) {
    error_log("Auth system error: " . $e->getMessage());
    http_response_code(500);
    die('Authentication system unavailable');
}

$action = $_POST['action'] ?? $_GET['action'] ?? '';
$message = '';
$messageType = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    switch ($action) {
        case 'login':
            $username = trim($_POST['username']);
            $password = $_POST['password'];

            if ($username && $password) {
                try {
                    // Use SSO authentication
                    $authResult = $ssoManager->authenticate($username, $password, $site['domain']);

                    if ($authResult['success']) {
                        $customer = $authResult['customer'];
                        $ssoToken = $authResult['sso_token'];

                        $_SESSION['customer_id'] = $customer['customer_id'];
                        $_SESSION['customer_data'] = $customer;
                        $_SESSION['site_domain'] = $site['domain'];
                        $_SESSION['sso_token'] = $ssoToken;

                        // Store SSO token in a secure cookie for cross-domain access
                        setcookie('aeims_sso_token', $ssoToken, [
                            'expires' => time() + (24 * 60 * 60), // 24 hours
                            'path' => '/',
                            'domain' => '.afterdarksystems.net', // Allows access across subdomains
                            'secure' => true,
                            'httponly' => true,
                            'samesite' => 'Lax'
                        ]);

                        header('Location: /dashboard.php');
                        exit;
                    } else {
                        $message = 'Invalid username or password';
                        $messageType = 'error';
                    }
                } catch (Exception $e) {
                    $message = 'Login failed: ' . $e->getMessage();
                    $messageType = 'error';
                }
            } else {
                $message = 'Username and password are required';
                $messageType = 'error';
            }
            break;

        case 'signup':
            $username = trim($_POST['username']);
            $email = trim($_POST['email']);
            $password = $_POST['password'];
            $confirmPassword = $_POST['confirm_password'];

            if ($username && $email && $password && $confirmPassword) {
                if ($password !== $confirmPassword) {
                    $message = 'Passwords do not match';
                    $messageType = 'error';
                } elseif (strlen($password) < 6) {
                    $message = 'Password must be at least 6 characters long';
                    $messageType = 'error';
                } else {
                    try {
                        $customer = $customerManager->createCustomer([
                            'username' => $username,
                            'email' => $email,
                            'password' => $password,
                            'site_domain' => $site['domain'],
                            'registration_ip' => $_SERVER['REMOTE_ADDR'] ?? 'unknown'
                        ]);

                        if ($customer) {
                            $_SESSION['customer_id'] = $customer['customer_id'];
                            $_SESSION['customer_data'] = $customer;
                            $_SESSION['site_domain'] = $site['domain'];

                            // Log successful registration
                            $customerManager->logActivity($customer['customer_id'], 'register', [
                                'site' => $site['domain'],
                                'ip' => $_SERVER['REMOTE_ADDR'] ?? 'unknown'
                            ]);

                            header('Location: /welcome.php');
                            exit;
                        } else {
                            $message = 'Registration failed. Please try again.';
                            $messageType = 'error';
                        }
                    } catch (Exception $e) {
                        $message = 'Registration failed: ' . $e->getMessage();
                        $messageType = 'error';
                    }
                }
            } else {
                $message = 'All fields are required';
                $messageType = 'error';
            }
            break;
    }
}

// Handle logout
if ($action === 'logout') {
    if (isset($_SESSION['customer_id'])) {
        try {
            // Perform global SSO logout
            $ssoManager->globalLogout($_SESSION['customer_id']);

            // Log logout activity
            $customerManager->logActivity($_SESSION['customer_id'], 'sso_logout', [
                'site' => $_SESSION['site_domain'] ?? $site['domain'],
                'ip' => $_SERVER['REMOTE_ADDR'] ?? 'unknown'
            ]);
        } catch (Exception $e) {
            error_log("SSO Logout error: " . $e->getMessage());
        }
    }

    // Clear SSO cookie
    setcookie('aeims_sso_token', '', [
        'expires' => time() - 3600,
        'path' => '/',
        'domain' => '.afterdarksystems.net',
        'secure' => true,
        'httponly' => true,
        'samesite' => 'Lax'
    ]);

    session_destroy();

    // Show logout confirmation with cross-domain logout iframes
    $logoutConfirmationHtml = generateLogoutConfirmation();
    echo $logoutConfirmationHtml;
    exit;
}

// If we get here with an error, redirect back to homepage with message
if ($message) {
    $_SESSION['auth_message'] = $message;
    $_SESSION['auth_message_type'] = $messageType;
    header('Location: /');
    exit;
}

// Default redirect if no action
header('Location: /');
exit;

/**
 * Generate logout confirmation page with cross-domain logout
 */
function generateLogoutConfirmation() {
    $trustedDomains = ['flirts.nyc', 'nycflirts.com', 'aeims.app', 'afterdarksystems.net'];

    $html = '<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Logging Out - Flirts NYC</title>
    <style>
        body { font-family: Arial, sans-serif; background: #1a1a1a; color: white; text-align: center; padding: 50px; }
        .logout-message { max-width: 500px; margin: 0 auto; }
        .spinner { border: 4px solid #333; border-top: 4px solid #ef4444; border-radius: 50%; width: 40px; height: 40px; animation: spin 2s linear infinite; margin: 20px auto; }
        @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
    </style>
</head>
<body>
    <div class="logout-message">
        <h2>Logging Out</h2>
        <div class="spinner"></div>
        <p>You are being logged out from all After Dark Systems sites...</p>
    </div>';

    // Add hidden iframes to logout from all domains
    foreach ($trustedDomains as $domain) {
        $html .= '<iframe src="https://' . $domain . '/sso/logout.php" style="display:none;"></iframe>';
    }

    $html .= '
    <script>
        setTimeout(function() {
            window.location.href = "/";
        }, 3000);
    </script>
</body>
</html>';

    return $html;
}
?>