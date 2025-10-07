# 🔐 SEXACOMMS LOGIN CREDENTIALS

## System Access Information
**Important:** Change all passwords after first login!

---

## **Admin Account** 
- **URL:** https://login.sexacomms.com
- **Email:** `admin@sexacomms.com`
- **Password:** `admin123`
- **Role:** Administrator
- **Access:** Full system administration, all features

---

## **Operator Account**
- **URL:** https://login.sexacomms.com  
- **Email:** `operator@sexacomms.com`
- **Password:** `admin123`
- **Role:** Operator
- **Access:** Operator dashboard, call handling, customer management

---

## **User Account**
- **URL:** https://login.sexacomms.com
- **Email:** `user@sexacomms.com` 
- **Password:** `admin123`
- **Role:** Regular User
- **Access:** Basic user features, calling, account management

---

## **System URLs**
- **Login/Main Frontend:** https://login.sexacomms.com or https://www.sexacomms.com
- **API Backend:** https://api.sexacomms.com
- **Individual Sites:**
  - https://flirts.nyc (PHP site)
  - https://nycflirts.com (PHP site)

---

## **Testing Locally**
If running locally on http://localhost:3001:
- Use the same credentials above
- The React app will be served from the telephony platform frontend
- Make sure to run: `docker-compose up -d --build`

---

## **Security Notes**
⚠️ **CRITICAL:** These are default development credentials
- Change all passwords immediately after first deployment
- The password hash in database: `$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi`
- This corresponds to plaintext: `admin123`

---

## **Database Access** (if needed)
From docker-compose.yml:
- **PostgreSQL (Core):** 
  - Host: localhost:5432
  - Database: aeims_core
  - User: aeims_user
  - Password: secure_password_123

- **MySQL (App):**
  - Host: localhost:3306  
  - Database: aeims_app
  - User: aeims_user
  - Password: secure_password_123

- **Redis:**
  - Host: localhost:6379
  - Password: secure_redis_pass

---

## **Quick Deployment Test**
```bash
# 1. Deploy the system
cd /Users/ryan/development/aeims-control
docker-compose down
docker-compose up -d --build

# 2. Wait for services to start (2-3 minutes)
docker-compose logs -f aeims-frontend

# 3. Test login
curl -I http://localhost:3000
# or visit http://localhost:3001/login directly

# 4. Login with admin@sexacomms.com / admin123
```

---

**Last Updated:** October 4, 2025  
**System:** SEXACOMMS AEIMS Telephony Platform