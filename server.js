/**
 * server.js — VulnBank: an intentionally vulnerable fake banking app.
 *
 * ============================================================
 *  FOR ETHICAL HACKING / SECURITY TRAINING LABS ONLY.
 *  DO NOT deploy this application on the public internet or
 *  use real personal/financial data with it. It contains
 *  DELIBERATE security vulnerabilities documented inline with
 *  "VULNERABILITY:" comments and summarized in README.md.
 * ============================================================
 */

const express = require('express');
const session = require('express-session');
const cookieParser = require('cookie-parser');
const bodyParser = require('body-parser');
const jwt = require('jsonwebtoken');
const path = require('path');
const { exec } = require('child_process');
const fs = require('fs');
const db = require('./db');

const app = express();
const PORT = process.env.PORT || 3000;

// VULNERABILITY: Hardcoded, weak JWT secret committed to source code.
const JWT_SECRET = 'bank123'; // trivially brute-forceable

app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));
app.use(cookieParser());
app.use(express.static(path.join(__dirname, 'public')));

// VULNERABILITY: Weak session secret + insecure cookie settings (no httpOnly/secure/sameSite enforcement).
app.use(session({
  secret: 'keyboard cat', // weak, guessable
  resave: false,
  saveUninitialized: true,
  cookie: { httpOnly: false } // allows access via document.cookie -> aids XSS demos
}));

// VULNERABILITY: Verbose error handler leaks stack traces to the client.
function sendError(res, err) {
  res.status(500).send('<pre>' + (err.stack || err) + '</pre>');
}

// ---------- AUTH ----------

// VULNERABILITY: SQL Injection - username/password concatenated directly into query.
app.post('/api/login', (req, res) => {
  const { username, password } = req.body;
  const query = `SELECT * FROM users WHERE username = '${username}' AND password = '${password}'`;
  db.all(query, (err, rows) => {
    if (err) return sendError(res, err);
    if (rows && rows.length > 0) {
      const user = rows[0];
      req.session.userId = user.id;

      // VULNERABILITY: JWT signed with weak secret; alg not restricted server-side on verify (see /api/verify).
      const token = jwt.sign(
        { id: user.id, username: user.username, is_admin: user.is_admin },
        JWT_SECRET,
        { algorithm: 'HS256', expiresIn: '2h' }
      );
      res.cookie('token', token, { httpOnly: false });
      res.json({ success: true, user: { id: user.id, username: user.username, is_admin: user.is_admin } });
    } else {
      res.status(401).json({ success: false, message: 'Invalid credentials' });
    }
  });
});

app.post('/api/logout', (req, res) => {
  req.session.destroy(() => {
    res.clearCookie('token');
    res.json({ success: true });
  });
});

// VULNERABILITY: Accepts JWT alg 'none' / doesn't strictly enforce algorithms allow-list.
function getUserFromToken(req) {
  const token = req.cookies.token;
  if (!token) return null;
  try {
    return jwt.verify(token, JWT_SECRET); // no `algorithms: ['HS256']` restriction
  } catch (e) {
    try {
      // Insecure fallback: decode without verifying signature at all
      return jwt.decode(token);
    } catch (e2) {
      return null;
    }
  }
}

app.get('/api/whoami', (req, res) => {
  const user = getUserFromToken(req);
  if (!user) return res.status(401).json({ success: false });
  res.json({ success: true, user });
});

// ---------- ACCOUNTS ----------

// VULNERABILITY: Broken Access Control / IDOR - any authenticated user can view ANY account
// by simply changing the numeric id in the URL. No ownership check performed.
app.get('/api/account/:id', (req, res) => {
  const user = getUserFromToken(req);
  if (!user) return res.status(401).json({ success: false, message: 'Not logged in' });

  const id = req.params.id; // used directly, no ownership validation
  db.get(`SELECT id, username, full_name, balance, is_admin FROM users WHERE id = ${id}`, (err, row) => {
    if (err) return sendError(res, err);
    if (!row) return res.status(404).json({ success: false, message: 'Not found' });
    res.json({ success: true, account: row });
  });
});

// VULNERABILITY: SQL Injection via search parameter (transaction history search box).
app.get('/api/transactions', (req, res) => {
  const user = getUserFromToken(req);
  if (!user) return res.status(401).json({ success: false });

  const search = req.query.search || '';
  const query = `SELECT * FROM transactions WHERE (from_account = ${user.id} OR to_account = ${user.id}) AND note LIKE '%${search}%'`;
  db.all(query, (err, rows) => {
    if (err) return sendError(res, err);
    res.json({ success: true, transactions: rows });
  });
});

// VULNERABILITY: CSRF - state-changing action with no CSRF token, relies solely on cookies.
// Also: no server-side validation that amount is a positive number/that funds exist (business logic flaw).
app.post('/api/transfer', (req, res) => {
  const user = getUserFromToken(req);
  if (!user) return res.status(401).json({ success: false });

  const { to_account, amount, note } = req.body;
  db.run(
    `INSERT INTO transactions (from_account, to_account, amount, note) VALUES (?, ?, ?, ?)`,
    [user.id, to_account, amount, note],
    function (err) {
      if (err) return sendError(res, err);
      db.run(`UPDATE users SET balance = balance - ? WHERE id = ?`, [amount, user.id]);
      db.run(`UPDATE users SET balance = balance + ? WHERE id = ?`, [amount, to_account]);
      res.json({ success: true, message: 'Transfer complete' });
    }
  );
});

// ---------- COMMENTS (Stored XSS) ----------

// VULNERABILITY: Stored XSS - comment body is stored and later rendered without sanitization/escaping
// by the frontend (see public/js/account.js which uses innerHTML).
app.get('/api/comments/:accountId', (req, res) => {
  const accountId = req.params.accountId;
  db.all(`SELECT * FROM comments WHERE account_id = ${accountId}`, (err, rows) => {
    if (err) return sendError(res, err);
    res.json({ success: true, comments: rows });
  });
});

app.post('/api/comments', (req, res) => {
  const user = getUserFromToken(req);
  if (!user) return res.status(401).json({ success: false });
  const { account_id, body } = req.body; // no HTML sanitization/escaping performed
  db.run(`INSERT INTO comments (account_id, author, body) VALUES (?, ?, ?)`,
    [account_id, user.username, body], function (err) {
      if (err) return sendError(res, err);
      res.json({ success: true });
    });
});

// ---------- "DIAGNOSTICS" (Command Injection) ----------

// VULNERABILITY: OS Command Injection - user input passed straight to a shell command.
app.post('/api/ping', (req, res) => {
  const user = getUserFromToken(req);
  if (!user) return res.status(401).json({ success: false });
  const { host } = req.body;
  exec(`ping -n 1 ${host}`, (err, stdout, stderr) => {
    res.json({ success: true, output: stdout || stderr || (err && err.message) });
  });
});

// ---------- STATEMENTS (Path Traversal) ----------

// VULNERABILITY: Path Traversal - filename taken from client and concatenated into a file path,
// allowing "../../../../etc/passwd" style access outside the intended statements directory.
app.get('/api/statement', (req, res) => {
  const user = getUserFromToken(req);
  if (!user) return res.status(401).json({ success: false });
  const file = req.query.file || 'welcome.txt';
  const filePath = path.join(__dirname, 'statements', file); // no sanitization of "..'"
  fs.readFile(filePath, 'utf8', (err, data) => {
    if (err) return res.status(404).send('File not found: ' + file);
    res.type('text/plain').send(data);
  });
});

// ---------- REFLECTED XSS ----------

// VULNERABILITY: Reflected XSS - the "q" param is echoed back into an HTML response unescaped.
app.get('/api/search-help', (req, res) => {
  const q = req.query.q || '';
  res.send(`<html><body><h3>Search results for: ${q}</h3><p>No help articles found.</p></body></html>`);
});

// ---------- ADMIN (Broken Access Control) ----------

// VULNERABILITY: Missing function-level access control - only checks a client-controllable
// "is_admin" claim inside the JWT (which was itself signed with a weak/known secret),
// and the check can also be bypassed with alg:none tokens accepted by getUserFromToken().
app.get('/api/admin/users', (req, res) => {
  const user = getUserFromToken(req);
  if (!user || !user.is_admin) return res.status(403).json({ success: false, message: 'Forbidden' });
  db.all('SELECT id, username, password, full_name, balance, is_admin FROM users', (err, rows) => {
    if (err) return sendError(res, err);
    res.json({ success: true, users: rows }); // also leaks plaintext passwords
  });
});

app.listen(PORT, () => {
  console.log(`VulnBank (lab) running at http://localhost:${PORT}`);
  console.log('WARNING: This app is intentionally vulnerable. Do not expose it publicly.');
});
