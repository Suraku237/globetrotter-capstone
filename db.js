// db.js - Sets up an intentionally insecure SQLite database for the vulnerable lab app.
// VULNERABILITY: Passwords are stored in PLAINTEXT (no hashing) - for lab purposes only!
const sqlite3 = require('sqlite3').verbose();
const path = require('path');

const db = new sqlite3.Database(path.join(__dirname, 'bank.db'));

db.serialize(() => {
  db.run(`CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE,
    password TEXT,
    full_name TEXT,
    balance REAL,
    is_admin INTEGER DEFAULT 0
  )`);

  db.run(`CREATE TABLE IF NOT EXISTS transactions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    from_account INTEGER,
    to_account INTEGER,
    amount REAL,
    note TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
  )`);

  db.run(`CREATE TABLE IF NOT EXISTS comments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id INTEGER,
    author TEXT,
    body TEXT
  )`);

  // Seed demo data (only if empty)
  db.get('SELECT COUNT(*) as c FROM users', (err, row) => {
    if (row && row.c === 0) {
      const stmt = db.prepare('INSERT INTO users (username, password, full_name, balance, is_admin) VALUES (?,?,?,?,?)');
      stmt.run('alice', 'alicepass123', 'Alice Anderson', 5000.00, 0);
      stmt.run('bob', 'bobpass123', 'Bob Brown', 12000.50, 0);
      stmt.run('admin', 'SuperSecretAdmin!2024', 'Bank Administrator', 999999.99, 1);
      stmt.finalize();

      db.run(`INSERT INTO transactions (from_account, to_account, amount, note) VALUES
        (2, 1, 250.00, 'Rent split'),
        (1, 2, 40.00, 'Lunch money')`);

      db.run(`INSERT INTO comments (account_id, author, body) VALUES
        (1, 'alice', 'Welcome to my account page!'),
        (2, 'bob', 'Saving up for a car <3')`);
    }
  });
});

module.exports = db;
