# Registration Timeout Troubleshooting Guide

## Problem
You're getting this error when trying to register:
```
❌ Registration error: Exception: Registration request timed out
```

## Root Causes

The registration timeout typically happens because **the backend server cannot reach the PostgreSQL database**. This can occur due to:

1. **PostgreSQL is not running** ❌ Most common
2. **Database connection string is incorrect** in `.env` file
3. **Database doesn't exist** or isn't initialized
4. **Network connectivity issues** between server and database
5. **Server isn't running** on port 4000

---

## Solution Steps

### Step 1: Check if PostgreSQL is Running

**Windows:**
```powershell
# Check if PostgreSQL service is running
Get-Service | Where-Object {$_.Name -like "*postgres*"}

# Start the service if it's stopped
Start-Service postgresql-x64-*
```

**Or check via UI:**
- Search for "Services" in Windows
- Look for PostgreSQL service
- Right-click → Start (if stopped)

### Step 2: Verify Database Connection String

Check your `.env` file:
```bash
cat wattbuddy-server/.env
```

Should contain:
```
DATABASE_URL=postgres://postgres:Albin@localhost:5432/wattbuddy
JWT_SECRET=abc123
PORT=4000
```

⚠️ **If DATABASE_URL is missing or wrong**, this is your issue!

### Step 3: Initialize the Database

If the database doesn't exist or tables are missing:

**Option A: Using psql (Command Line)**
```powershell
# Connect to PostgreSQL
psql -U postgres -d postgres

# Inside psql:
CREATE DATABASE wattbuddy;
\c wattbuddy
\i 'e:/wattBuddy/wattbuddy-server/init.sql'
\q
```

**Option B: Using PgAdmin (GUI)**
1. Open PgAdmin (usually at http://localhost:5050)
2. Create database named `wattbuddy`
3. Right-click database → Query Tool
4. Open and run `wattbuddy-server/init.sql`

### Step 4: Start the Backend Server

```powershell
cd e:\wattBuddy\wattbuddy-server
npm install  # First time only
npm start
```

You should see:
```
🚀 Server running on http://0.0.0.0:4000
✅ Database connection successful
```

### Step 5: Test the Server

From another terminal:
```powershell
# Test if server is responding
curl http://localhost:4000

# Test registration endpoint (Windows PowerShell)
$body = @{
    username = "testuser"
    email = "test@example.com"
    consumer_number = "12345"
    password = "password123"
} | ConvertTo-Json

curl -Method POST `
  -Uri http://localhost:4000/api/auth/register `
  -Headers @{"Content-Type"="application/json"} `
  -Body $body
```

### Step 6: Run the Flutter App

Make sure the app is pointing to the correct server:
- **Android Emulator**: `http://10.0.2.2:4000/api/auth` ✅
- **Physical Phone**: `http://YOUR_PC_IP:4000/api/auth` (change in `api_service.dart`)
- **Web/Desktop**: `http://localhost:4000/api/auth`

---

## Diagnostic Checklist

- [ ] PostgreSQL service is **running**
- [ ] Database `wattbuddy` **exists**
- [ ] Tables are **initialized** (ran init.sql)
- [ ] `.env` file has correct `DATABASE_URL`
- [ ] Node.js backend is **running** on port 4000
- [ ] App is using correct server IP/URL
- [ ] Firewall allows connections to port 4000

## Error Messages & Solutions

### "Cannot reach database"
→ PostgreSQL isn't running or connection string is wrong

### "Database connection timeout"
→ PostgreSQL is running but not responding (firewall issue?)

### "User already exists"
→ Registration worked but user was already created

### "Invalid credentials" (on login)
→ Check username/password and ensure user exists in database

---

## Quick Reset (Nuclear Option)

If everything is broken, reset everything:

```powershell
# 1. Stop the server (Ctrl+C in terminal)

# 2. Stop PostgreSQL
Stop-Service postgresql-x64-*

# 3. Delete old database (optional)
# In PgAdmin or psql:
DROP DATABASE wattbuddy;

# 4. Restart PostgreSQL
Start-Service postgresql-x64-*

# 5. Create fresh database
psql -U postgres -d postgres
CREATE DATABASE wattbuddy;
\c wattbuddy
\i 'e:/wattBuddy/wattbuddy-server/init.sql'
\q

# 6. Restart backend
cd e:\wattBuddy\wattbuddy-server
npm start

# 7. Try registration again
```

---

## Server Logs

When running the server with `npm start`, watch for these logs:

✅ **Good signs:**
```
🚀 Server running on http://0.0.0.0:4000
✅ Database connection successful
📥 Register API hit
💾 Inserting user into database...
✅ Registration successful
```

❌ **Bad signs:**
```
❌ Database connection FAILED
❌ Registration error: timeout
Cannot reach database
ECONNREFUSED - connection refused
```

---

## Detailed Error Meanings

| Error | Cause | Solution |
|-------|-------|----------|
| `ECONNREFUSED` | PostgreSQL not running or wrong port | Start PostgreSQL service |
| `Database timeout` | Database taking too long to respond | Check database size/performance |
| `User already exists` | Registration worked, user created successfully | Try logging in instead |
| `All fields are required` | Missing username/email/consumer_number/password | Fill all fields in registration form |

---

## Contact & Support

If issues persist:
1. Check the error message in the console carefully
2. Verify PostgreSQL is running: `Get-Service postgresql*`
3. Verify server is running: Open http://localhost:4000 in browser
4. Check `.env` file configuration
5. Review server logs for detailed error information
