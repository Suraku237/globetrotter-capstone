const assert = require('node:assert/strict');
const { before, after, test } = require('node:test');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { promisify } = require('node:util');
const { execFile } = require('node:child_process');
const sqlite3 = require('sqlite3').verbose();

const execute = promisify(execFile);
let directory;
let databasePath;
let store;

async function createFixture(file, sql) {
  let database;
  await new Promise((resolve, reject) => {
    database = new sqlite3.Database(file, err => err ? reject(err) : resolve());
  });
  try {
    await new Promise((resolve, reject) => database.exec(sql, err => err ? reject(err) : resolve()));
  } finally {
    await new Promise((resolve, reject) => database.close(err => err ? reject(err) : resolve()));
  }
}

function migrateInChild(file) {
  return execute(process.execPath, ['-e', `
    const store = require('./database');
    store.ready.then(() => store.db.close(err => {
      if (err) { console.error(err); process.exitCode = 1; }
    })).catch(err => {
      console.error(err);
      process.exitCode = 1;
      store.db.close();
    });
  `], {
    cwd: path.join(__dirname, '..'),
    env: { ...process.env, BANK_DB_PATH: file },
    timeout: 15000
  });
}

before(async () => {
  directory = fs.mkdtempSync(path.join(os.tmpdir(), 'vuln-bank-migration-'));
  databasePath = path.join(directory, 'legacy.db');
  await createFixture(databasePath, `
    CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE,
      password TEXT, full_name TEXT, balance REAL, is_admin INTEGER DEFAULT 0);
    CREATE TABLE transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, from_account INTEGER,
      to_account INTEGER, amount REAL, note TEXT, created_at TEXT DEFAULT CURRENT_TIMESTAMP);
    CREATE TABLE comments (id INTEGER PRIMARY KEY AUTOINCREMENT, account_id INTEGER, author TEXT, body TEXT);
    INSERT INTO users VALUES (1, 'alice', 'custom-alice', 'Existing Alice', 4250.75, 0);
    INSERT INTO users VALUES (2, 'bob', 'custom-bob', 'Existing Bob', 123.45, 1);
    INSERT INTO users VALUES (3, 'admin', 'custom-admin', 'Existing Admin', 999.99, 1);
    INSERT INTO transactions VALUES (1, 1, 2, 4.25, 'Existing note', '2026-10-01 12:00:00');
    INSERT INTO comments VALUES (1, 1, 'alice', '<b>Existing lab comment</b>');
  `);
  process.env.BANK_DB_PATH = databasePath;
  store = require(path.join(__dirname, '..', 'database'));
  await store.ready;
});

after(async () => {
  if (store) await new Promise((resolve, reject) => store.db.close(err => err ? reject(err) : resolve()));
  if (directory) fs.rmSync(directory, { recursive: true, force: true });
});

test('migration preserves existing balances, credentials, roles, comments, and history', async () => {
  const users = await store.all(store.db, 'SELECT * FROM users ORDER BY id');
  assert.deepEqual(users.map(user => user.balance), [4250.75, 123.45, 999.99]);
  assert.deepEqual(users.map(user => user.password), ['custom-alice', 'custom-bob', 'custom-admin']);
  assert.deepEqual(users.map(user => user.is_admin), [0, 1, 1]);
  assert.deepEqual(users.map(user => user.phone_number), ['+237600000001', '+237600000002', '+237600000003']);
  assert.ok(users.every(user => user.transfer_pin === '1234'));
  assert.equal((await store.all(store.db, 'PRAGMA table_info(transactions)')).length, 6);
  assert.equal((await store.get(store.db, 'SELECT * FROM transactions WHERE id = 1')).note, 'Existing note');
  assert.equal((await store.get(store.db, 'SELECT * FROM comments WHERE id = 1')).body, '<b>Existing lab comment</b>');
});

test('running migration again does not reset user data or reseed history', async () => {
  await store.run(store.db, "UPDATE users SET phone_number = '+2250700000001', transfer_pin = '0077' WHERE id = 1");
  const beforeRows = await store.all(store.db, 'SELECT * FROM users ORDER BY id');
  await migrateInChild(databasePath);
  assert.deepEqual(await store.all(store.db, 'SELECT * FROM users ORDER BY id'), beforeRows);
  assert.equal((await store.get(store.db, 'SELECT COUNT(*) AS count FROM transactions')).count, 1);
  assert.equal((await store.get(store.db, 'SELECT COUNT(*) AS count FROM comments')).count, 1);
});

test('failed migrations report the error and roll back schema changes instead of replacing data', async () => {
  const file = path.join(directory, 'conflict.db');
  await createFixture(file, `
    CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT UNIQUE, password TEXT,
      full_name TEXT, balance REAL, is_admin INTEGER DEFAULT 0, phone_number TEXT);
    INSERT INTO users VALUES (1, 'one', 'demo', 'One', 10.25, 0, '+237650000001');
    INSERT INTO users VALUES (2, 'two', 'demo', 'Two', 20.50, 0, '+237650000001');
  `);
  await assert.rejects(migrateInChild(file), error => {
    assert.match(error.stderr, /UNIQUE constraint failed/);
    return true;
  });
  let database;
  await new Promise((resolve, reject) => {
    database = new sqlite3.Database(file, err => err ? reject(err) : resolve());
  });
  try {
    const columns = await store.all(database, 'PRAGMA table_info(users)');
    assert.equal(columns.some(column => column.name === 'transfer_pin'), false);
    assert.deepEqual((await store.all(database, 'SELECT balance FROM users ORDER BY id')).map(row => row.balance), [10.25, 20.5]);
    assert.equal(await store.get(database, "SELECT name FROM sqlite_master WHERE name = 'mobile_transfers'"), undefined);
  } finally {
    await new Promise((resolve, reject) => database.close(err => err ? reject(err) : resolve()));
  }
});
