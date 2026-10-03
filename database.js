// Sets up an intentionally insecure SQLite database for the vulnerable lab app.
// VULNERABILITY: Passwords and demo transaction PINs are stored in plaintext.
const sqlite3 = require('sqlite3').verbose();
const path = require('path');

const databasePath = path.resolve(process.env.BANK_DB_PATH || path.join(__dirname, 'bank.db'));
const demoUsers = [
  ['alice', 'alicepass123', 'Alice Anderson', 5000.00, 0, '+237600000001'],
  ['bob', 'bobpass123', 'Bob Brown', 12000.50, 0, '+237600000002'],
  ['admin', 'admin', 'Bank Administrator', 999999.99, 1, '+237600000003']
];

function connect(mode = sqlite3.OPEN_READWRITE | sqlite3.OPEN_CREATE) {
  let connection;
  const opened = new Promise((resolve, reject) => {
    connection = new sqlite3.Database(databasePath, mode, err => {
      if (err) return reject(err);
      connection.configure('busyTimeout', 5000);
      resolve(connection);
    });
  });
  return { db: connection, opened };
}

function run(connection, sql, params = []) {
  return new Promise((resolve, reject) => {
    connection.run(sql, params, function (err) {
      if (err) return reject(err);
      resolve({ lastID: this.lastID, changes: this.changes });
    });
  });
}

function get(connection, sql, params = []) {
  return new Promise((resolve, reject) => {
    connection.get(sql, params, (err, row) => err ? reject(err) : resolve(row));
  });
}

function all(connection, sql, params = []) {
  return new Promise((resolve, reject) => {
    connection.all(sql, params, (err, rows) => err ? reject(err) : resolve(rows));
  });
}

async function transaction(connection, work) {
  await run(connection, 'BEGIN IMMEDIATE');
  try {
    const result = await work(connection);
    await run(connection, 'COMMIT');
    return result;
  } catch (err) {
    try {
      await run(connection, 'ROLLBACK');
    } catch (rollbackError) {
      throw new AggregateError([err, rollbackError], 'Database transaction and rollback failed');
    }
    throw err;
  }
}

async function withTransaction(work) {
  // A separate connection keeps legacy requests out of a payment's transaction.
  const connection = await connect(sqlite3.OPEN_READWRITE).opened;
  try {
    return await transaction(connection, work);
  } finally {
    await new Promise((resolve, reject) => {
      connection.close(err => err ? reject(err) : resolve());
    });
  }
}

const connection = connect();
const db = connection.db;
const ready = connection.opened.then(() => transaction(db, async () => {
  await run(db, `CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE,
    password TEXT,
    full_name TEXT,
    balance REAL,
    is_admin INTEGER DEFAULT 0
  )`);

  const columns = await all(db, 'PRAGMA table_info(users)');
  if (!columns.some(column => column.name === 'phone_number')) {
    await run(db, 'ALTER TABLE users ADD COLUMN phone_number TEXT');
  }
  if (!columns.some(column => column.name === 'transfer_pin')) {
    await run(db, "ALTER TABLE users ADD COLUMN transfer_pin TEXT DEFAULT '1234'");
  }

  // Keep these six columns intact for the existing UNION-based SQL injection lab.
  await run(db, `CREATE TABLE IF NOT EXISTS transactions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    from_account INTEGER,
    to_account INTEGER,
    amount REAL,
    note TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
  )`);
  await run(db, `CREATE TABLE IF NOT EXISTS comments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id INTEGER,
    author TEXT,
    body TEXT
  )`);
  await run(db, `CREATE TABLE IF NOT EXISTS mobile_transfers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    transaction_id INTEGER NOT NULL UNIQUE REFERENCES transactions(id),
    sender_id INTEGER NOT NULL REFERENCES users(id),
    provider TEXT NOT NULL CHECK (provider IN ('mtn', 'orange')),
    recipient_phone TEXT NOT NULL,
    amount REAL NOT NULL CHECK (amount > 0),
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
  )`);

  const row = await get(db, 'SELECT COUNT(*) as c FROM users');
  if (row.c === 0) {
    for (const user of demoUsers) {
      await run(db, `INSERT INTO users
        (username, password, full_name, balance, is_admin, phone_number)
        VALUES (?, ?, ?, ?, ?, ?)`, user);
    }
    await run(db, `INSERT INTO transactions (from_account, to_account, amount, note) VALUES
        (2, 1, 250.00, 'Rent split'),
        (1, 2, 40.00, 'Lunch money')`);
    await run(db, `INSERT INTO comments (account_id, author, body) VALUES
        (1, 'alice', 'Welcome to my account page!'),
        (2, 'bob', 'Saving up for a car <3')`);
  }

  for (const user of demoUsers) {
    await run(db, 'UPDATE users SET phone_number = ? WHERE username = ? AND phone_number IS NULL',
      [user[5], user[0]]);
  }
  await run(db, "UPDATE users SET transfer_pin = '1234' WHERE transfer_pin IS NULL");
  await run(db, 'CREATE UNIQUE INDEX IF NOT EXISTS users_phone_number ON users (phone_number)');
}));

module.exports = { db, ready, run, get, all, withTransaction };
