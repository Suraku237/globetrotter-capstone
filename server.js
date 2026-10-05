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
const { db, ready, run, get, all, withTransaction } = require('./database');

const app = express();
const PORT = process.env.PORT || 3000;

// VULNERABILITY: Hardcoded, weak JWT secret committed to source code.
const JWT_SECRET = 'bank123'; // trivially brute-forceable
const MOBILE_PROVIDERS = { mtn: 'MTN MoMo', orange: 'Orange Money' };

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

function createSession(req, res, user) {
  req.session.userId = user.id;
  // VULNERABILITY: Keep the weak secret and client-controlled role claims for the lab.
  const token = jwt.sign(
    { id: user.id, username: user.username, is_admin: user.is_admin },
    JWT_SECRET,
    { algorithm: 'HS256', expiresIn: '2h' }
  );
  res.cookie('token', token, { httpOnly: false });
  return { id: user.id, username: user.username, is_admin: user.is_admin };
}

function normalizePhone(value) {
  if (typeof value !== 'string') return null;
  const phone = value.replace(/[\s()-]/g, '');
  return /^\+[1-9]\d{7,14}$/.test(phone) ? phone : null;
}

app.post('/api/signup', async (req, res) => {
  const { username, password, full_name, phone_number, pin } = req.body || {};
  const name = typeof username === 'string' ? username.trim() : '';
  const fullName = typeof full_name === 'string' ? full_name.trim() : '';
  const phone = normalizePhone(phone_number);
  if (!/^[A-Za-z0-9_]{3,40}$/.test(name)) {
    return res.status(400).json({ success: false, message: 'Use 3-40 letters, numbers or underscores for your username.' });
  }
  if (fullName.length < 2 || fullName.length > 100) {
    return res.status(400).json({ success: false, message: 'Enter a name between 2 and 100 characters.' });
  }
  if (typeof password !== 'string' || password.length < 4 || password.length > 128) {
    return res.status(400).json({ success: false, message: 'Choose a demo password between 4 and 128 characters.' });
  }
  if (!phone) {
    return res.status(400).json({ success: false, message: 'Use an international demo phone number, for example +237600000004.' });
  }
  if (typeof pin !== 'string' || !/^\d{4}$/.test(pin)) {
    return res.status(400).json({ success: false, message: 'Choose a four-digit demo PIN. Never use a real mobile-money PIN.' });
  }
  try {
    const result = await run(db, `INSERT INTO users
      (username, password, full_name, balance, is_admin, phone_number, transfer_pin)
      VALUES (?, ?, ?, 5000, 0, ?, ?)`, [name, password, fullName, phone, pin]);
    const user = createSession(req, res, { id: result.lastID, username: name, is_admin: 0 });
    res.status(201).json({ success: true, user, message: 'Demo account created with 5,000 FCFA of simulated funds.' });
  } catch (err) {
    if (err.code === 'SQLITE_CONSTRAINT' &&
        /users\.(username|phone_number)/.test(err.message)) {
      return res.status(409).json({ success: false, message: 'That username or phone number is already registered.' });
    }
    sendError(res, err);
  }
});

// VULNERABILITY: SQL Injection - username/password concatenated directly into query.
app.post('/api/login', (req, res) => {
  const { username, password } = req.body;
  const query = `SELECT * FROM users WHERE username = '${username}' AND password = '${password}'`;
  db.all(query, (err, rows) => {
    if (err) return sendError(res, err);
    if (rows && rows.length > 0) {
      const user = rows[0];
      res.json({ success: true, user: createSession(req, res, user) });
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
  db.get(`SELECT id, username, full_name, balance, is_admin, phone_number FROM users WHERE id = ${id}`, (err, row) => {
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
  db.get('SELECT id FROM users WHERE id = ?', [to_account], (lookupErr, recipient) => {
    if (lookupErr) return sendError(res, lookupErr);
    if (!recipient) return res.status(404).json({ success: false, message: 'Account not found.' });
    db.run(
      `INSERT INTO transactions (from_account, to_account, amount, note) VALUES (?, ?, ?, ?)`,
      [user.id, recipient.id, amount, note],
      function (err) {
        if (err) return sendError(res, err);
        db.run(`UPDATE users SET balance = balance - ? WHERE id = ?`, [amount, user.id]);
        db.run(`UPDATE users SET balance = balance + ? WHERE id = ?`, [amount, recipient.id]);
        res.json({ success: true, message: 'Transfer complete' });
      }
    );
  });
});

// ---------- SIMULATED MOBILE MONEY ----------

function mobileReceipt(row) {
  return {
    ...row,
    reference: `VB-${row.provider.toUpperCase()}-${String(row.id).padStart(6, '0')}`,
    provider_name: MOBILE_PROVIDERS[row.provider],
    simulated: true
  };
}

app.get('/api/mobile-transfers', async (req, res) => {
  const user = getUserFromToken(req);
  if (!user) return res.status(401).json({ success: false, message: 'Not logged in' });
  try {
    const rows = await all(db, `SELECT * FROM mobile_transfers
      WHERE sender_id = ? ORDER BY id DESC LIMIT 20`, [user.id]);
    res.json({ success: true, transfers: rows.map(mobileReceipt) });
  } catch (err) {
    sendError(res, err);
  }
});

app.post('/api/mobile-transfers', async (req, res) => {
  const user = getUserFromToken(req);
  if (!user) return res.status(401).json({ success: false, message: 'Not logged in' });
  const { provider, phone_number, amount, pin, note = '' } = req.body || {};
  const phone = normalizePhone(phone_number);
  const amountText = typeof amount === 'number' ? String(amount) :
    typeof amount === 'string' ? amount.trim() : '';
  const value = Number(amountText);
  if (typeof provider !== 'string' || !Object.hasOwn(MOBILE_PROVIDERS, provider)) {
    return res.status(400).json({ success: false, message: 'Choose MTN MoMo or Orange Money.' });
  }
  if (!phone) {
    return res.status(400).json({ success: false, message: 'Enter an international demo phone number, for example +237600000004.' });
  }
  if (!/^\d+(?:\.\d{1,2})?$/.test(amountText) || value <= 0 ||
      !Number.isSafeInteger(Math.round(value * 100))) {
    return res.status(400).json({ success: false, message: 'Enter a positive FCFA amount with at most two decimal places.' });
  }
  if (typeof pin !== 'string' || !/^\d{4}$/.test(pin)) {
    return res.status(400).json({ success: false, message: 'Enter your four-digit VulnBank demo PIN, not an operator PIN.' });
  }
  if (typeof note !== 'string' || note.length > 140) {
    return res.status(400).json({ success: false, message: 'The transfer note must be at most 140 characters.' });
  }
  try {
    const result = await withTransaction(async connection => {
      const sender = await get(connection, 'SELECT balance, transfer_pin FROM users WHERE id = ?', [user.id]);
      if (!sender) return { status: 404, error: 'Account not found.' };
      if (sender.transfer_pin !== pin) return { status: 403, error: 'Incorrect demo PIN.' };
      if (typeof sender.balance !== 'number' || !Number.isFinite(sender.balance)) {
        return { status: 409, error: 'This account has an invalid balance. Ask the lab administrator to inspect it.' };
      }
      const recipient = await get(connection, 'SELECT id, username FROM users WHERE phone_number = ?', [phone]);
      if (!recipient) return { status: 404, error: 'Account not found.' };
      if (recipient.id === user.id) return { status: 400, error: 'You cannot transfer money to your own account.' };
      if (sender.balance < value) return { status: 400, error: 'Insufficient demo funds for this transfer.' };
      const description = `${MOBILE_PROVIDERS[provider]} transfer to ${phone}${note.trim() ? ' - ' + note.trim() : ''}`;
      const ledger = await run(connection, `INSERT INTO transactions
        (from_account, to_account, amount, note) VALUES (?, ?, ?, ?)`, [user.id, recipient.id, value, description]);
      const payment = await run(connection, `INSERT INTO mobile_transfers
        (transaction_id, sender_id, provider, recipient_phone, amount) VALUES (?, ?, ?, ?, ?)`,
      [ledger.lastID, user.id, provider, phone, value]);
      await run(connection, 'UPDATE users SET balance = balance - ? WHERE id = ?', [value, user.id]);
      await run(connection, 'UPDATE users SET balance = balance + ? WHERE id = ?', [value, recipient.id]);
      const transfer = await get(connection, 'SELECT * FROM mobile_transfers WHERE id = ?', [payment.lastID]);
      const account = await get(connection, 'SELECT balance FROM users WHERE id = ?', [user.id]);
      return { transfer: mobileReceipt(transfer), balance: account.balance, recipient: recipient.username };
    });
    if (result.error) {
      return res.status(result.status).json({ success: false, message: result.error });
    }
    res.status(201).json({
      success: true,
      message: `${value.toFixed(2)} FCFA transferred successfully to ${result.recipient} (${phone}) via ${MOBILE_PROVIDERS[provider]}.`,
      ...result
    });
  } catch (err) {
    sendError(res, err);
  }
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
  db.all('SELECT id, username, password, full_name, balance, is_admin, phone_number FROM users', (err, rows) => {
    if (err) return sendError(res, err);
    res.json({ success: true, users: rows }); // also leaks plaintext passwords
  });
});

app.patch('/api/admin/users/:id/role', async (req, res) => {
  const user = getUserFromToken(req);
  if (!user || !user.is_admin) return res.status(403).json({ success: false, message: 'Forbidden' });
  const id = Number(req.params.id);
  const { role } = req.body || {};
  if (!Number.isSafeInteger(id) || id < 1 || !['user', 'admin'].includes(role)) {
    return res.status(400).json({ success: false, message: 'Choose a valid user and role.' });
  }
  if (id === Number(user.id)) {
    return res.status(400).json({ success: false, message: 'You cannot change your own role in this panel.' });
  }
  try {
    const result = await run(db, 'UPDATE users SET is_admin = ? WHERE id = ?', [role === 'admin' ? 1 : 0, id]);
    if (result.changes !== 1) {
      return res.status(404).json({ success: false, message: 'User not found.' });
    }
    res.json({ success: true, message: 'Role updated. The user must sign in again to refresh their role.' });
  } catch (err) {
    sendError(res, err);
  }
});

if (require.main === module) {
  ready.then(() => {
    const server = app.listen(PORT, () => {
      console.log(`VulnBank (lab) running at http://localhost:${server.address().port}`);
      console.log('WARNING: This app is intentionally vulnerable. Do not expose it publicly.');
    });
  }).catch(err => {
    console.error('Database initialization failed:', err);
    process.exitCode = 1;
    db.close(closeError => {
      if (closeError) console.error('Database cleanup failed:', closeError);
    });
  });
}

module.exports = { app, db, ready };
