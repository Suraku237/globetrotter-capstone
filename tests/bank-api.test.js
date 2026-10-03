const assert = require('node:assert/strict');
const { before, after, test } = require('node:test');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

let directory;
let bank;
let store;
let server;
let base;
let sequence = 100;

before(async () => {
  directory = fs.mkdtempSync(path.join(os.tmpdir(), 'vuln-bank-api-'));
  process.env.BANK_DB_PATH = path.join(directory, 'bank.db');
  store = require(path.join(__dirname, '..', 'database'));
  bank = require(path.join(__dirname, '..', 'server'));
  await bank.ready;
  await new Promise(resolve => {
    server = bank.app.listen(0, '127.0.0.1', resolve);
  });
  base = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  if (server) {
    await new Promise(resolve => {
      server.close(resolve);
      server.closeAllConnections();
    });
  }
  if (bank) await new Promise((resolve, reject) => bank.db.close(err => err ? reject(err) : resolve()));
  if (directory) fs.rmSync(directory, { recursive: true, force: true });
});

async function api(route, { method = 'GET', body, cookie } = {}) {
  const headers = {};
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (cookie) headers.Cookie = cookie;
  const response = await fetch(base + route, {
    method, headers, body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await response.text();
  const cookies = response.headers.getSetCookie();
  return {
    status: response.status,
    text,
    data: (response.headers.get('content-type') || '').includes('application/json') ? JSON.parse(text) : null,
    cookie: cookies.map(value => value.split(';')[0]).join('; '),
    cookies
  };
}

async function signup(overrides = {}) {
  sequence += 1;
  const body = {
    username: `customer_${sequence}`,
    password: 'demo_pass',
    full_name: 'Demo Customer',
    phone_number: `+237650${String(sequence).padStart(6, '0')}`,
    pin: '0042',
    ...overrides
  };
  const response = await api('/api/signup', { method: 'POST', body });
  assert.equal(response.status, 201, response.text);
  return { ...response, credentials: body };
}

async function login(username = 'admin', password = 'admin') {
  const result = await api('/api/login', { method: 'POST', body: { username, password } });
  assert.equal(result.status, 200, result.text);
  return result;
}

function payment(overrides = {}) {
  return { provider: 'mtn', phone_number: '+237690123456', amount: '12.50', pin: '0042', ...overrides };
}

test('fresh databases retain demo accounts and the legacy transaction shape', async () => {
  const users = await store.all(bank.db, 'SELECT username, balance, transfer_pin FROM users ORDER BY id');
  assert.deepEqual(users.map(user => user.username), ['alice', 'bob', 'admin']);
  assert.deepEqual(users.map(user => user.balance), [5000, 12000.5, 999999.99]);
  assert.ok(users.every(user => user.transfer_pin === '1234'));
  const columns = await store.all(bank.db, 'PRAGMA table_info(transactions)');
  assert.equal(columns.length, 6);
});

test('signup creates a regular user, preserves a leading-zero PIN, and starts with 5000 FCFA', async () => {
  const customer = await signup({ is_admin: 1, role: 'admin', phone_number: '+237 650-000-099' });
  assert.equal(customer.data.user.is_admin, 0);
  const row = await store.get(bank.db, 'SELECT * FROM users WHERE id = ?', [customer.data.user.id]);
  assert.equal(row.balance, 5000);
  assert.equal(row.phone_number, '+237650000099');
  assert.equal(row.transfer_pin, '0042');
  assert.equal(row.password, customer.credentials.password);
  const profile = await api(`/api/account/${row.id}`, { cookie: customer.cookie });
  assert.equal(profile.data.account.balance, 5000);
  assert.equal(profile.data.account.phone_number, row.phone_number);
  assert.equal(profile.data.account.transfer_pin, undefined);
});

test('signup rejects duplicates and invalid inputs without creating accounts', async () => {
  const customer = await signup();
  const beforeCount = await store.get(bank.db, 'SELECT COUNT(*) AS count FROM users');
  for (const body of [
    { ...customer.credentials, phone_number: '+237655000001' },
    { ...customer.credentials, username: 'another_customer' }
  ]) {
    assert.equal((await api('/api/signup', { method: 'POST', body })).status, 409);
  }
  for (const change of [
    { username: 'ab' }, { pin: '42' }, { pin: 1234 },
    { phone_number: '123' }, { full_name: '' }, { password: 'x' }
  ]) {
    const response = await api('/api/signup', { method: 'POST', body: { ...customer.credentials, ...change } });
    assert.equal(response.status, 400);
    assert.equal(response.data.success, false);
  }
  assert.deepEqual(await store.get(bank.db, 'SELECT COUNT(*) AS count FROM users'), beforeCount);
});

test('administrators manage other roles and users refresh claims by signing in again', async () => {
  const administrator = await login();
  const customer = await signup();
  const route = `/api/admin/users/${customer.data.user.id}/role`;
  assert.equal((await api('/api/admin/users', { cookie: customer.cookie })).status, 403);
  assert.equal((await api(route, { method: 'PATCH', cookie: customer.cookie, body: { role: 'admin' } })).status, 403);
  assert.equal((await api(route, { method: 'PATCH', cookie: administrator.cookie, body: { role: 'admin' } })).status, 200);
  const oldSession = await api('/api/whoami', { cookie: customer.cookie });
  assert.equal(oldSession.data.user.is_admin, 0);
  const refreshed = await login(customer.credentials.username, customer.credentials.password);
  assert.equal(refreshed.data.user.is_admin, 1);
  assert.equal((await api('/api/admin/users', { cookie: refreshed.cookie })).status, 200);
  assert.equal((await api('/api/admin/users/3/role', {
    method: 'PATCH', cookie: administrator.cookie, body: { role: 'user' }
  })).status, 400);
  assert.equal((await api(route, {
    method: 'PATCH', cookie: administrator.cookie, body: { role: 'superuser' }
  })).status, 400);
});

test('MTN and Orange payments debit funds, persist receipts, and accept unregistered numbers', async () => {
  for (const provider of ['mtn', 'orange']) {
    const customer = await signup();
    const response = await api('/api/mobile-transfers', {
      method: 'POST', cookie: customer.cookie,
      body: payment({ provider, phone_number: '+237 690-123-456' })
    });
    assert.equal(response.status, 201, response.text);
    assert.equal(response.data.balance, 4987.5);
    assert.equal(response.data.transfer.provider, provider);
    assert.equal(response.data.transfer.recipient_phone, '+237690123456');
    assert.equal(response.data.transfer.simulated, true);
    assert.match(response.data.transfer.reference, /^VB-(MTN|ORANGE)-\d{6,}$/);
    assert.match(response.data.message, /12\.50 FCFA transferred successfully/);
    const history = await api('/api/mobile-transfers', { cookie: customer.cookie });
    assert.equal(history.data.transfers.length, 1);
    assert.equal(history.data.transfers[0].reference, response.data.transfer.reference);
    const ledger = await store.get(bank.db, 'SELECT * FROM transactions WHERE id = ?', [response.data.transfer.transaction_id]);
    assert.equal(ledger.from_account, customer.data.user.id);
    assert.equal(ledger.to_account, null);
    assert.equal(ledger.amount, 12.5);
    assert.match(ledger.note, /transfer to \+237690123456/);
  }
});

test('payments to a registered contact still simulate an external wallet, not a bank-account credit', async () => {
  const customer = await signup();
  const beforeBalance = await store.get(bank.db, 'SELECT balance FROM users WHERE id = 2');
  const response = await api('/api/mobile-transfers', {
    method: 'POST', cookie: customer.cookie, body: payment({ phone_number: '+237600000002' })
  });
  assert.equal(response.status, 201);
  assert.deepEqual(await store.get(bank.db, 'SELECT balance FROM users WHERE id = 2'), beforeBalance);
});

test('failed mobile payments return explicit errors without changing balances or ledgers', async () => {
  const customer = await signup();
  const id = customer.data.user.id;
  for (const [change, status] of [
    [{ pin: '9999' }, 403], [{ provider: 'unknown' }, 400],
    [{ phone_number: 'invalid' }, 400], [{ amount: '-1.00' }, 400],
    [{ amount: '0' }, 400], [{ amount: '1.001' }, 400],
    [{ amount: '5000.01' }, 400], [{ pin: 42 }, 400]
  ]) {
    const response = await api('/api/mobile-transfers', {
      method: 'POST', cookie: customer.cookie, body: payment(change)
    });
    assert.equal(response.status, status, response.text);
    assert.equal(response.data.success, false);
    assert.ok(response.data.message);
  }
  assert.equal((await store.get(bank.db, 'SELECT balance FROM users WHERE id = ?', [id])).balance, 5000);
  assert.equal((await store.get(bank.db, 'SELECT COUNT(*) AS count FROM transactions WHERE from_account = ?', [id])).count, 0);
  assert.equal((await api('/api/mobile-transfers', { cookie: customer.cookie })).data.transfers.length, 0);
  assert.equal((await api('/api/mobile-transfers', { method: 'POST', body: payment() })).status, 401);
});

test('a database failure rolls back the debit and both payment records', async () => {
  const customer = await signup();
  const id = customer.data.user.id;
  await store.run(bank.db, `CREATE TRIGGER reject_test_debit BEFORE UPDATE OF balance ON users
    WHEN OLD.id = ${id} BEGIN SELECT RAISE(ABORT, 'simulated debit failure'); END`);
  try {
    const response = await api('/api/mobile-transfers', {
      method: 'POST', cookie: customer.cookie, body: payment()
    });
    assert.equal(response.status, 500);
    assert.match(response.text, /simulated debit failure/);
    assert.equal((await store.get(bank.db, 'SELECT balance FROM users WHERE id = ?', [id])).balance, 5000);
    assert.equal((await store.get(bank.db, 'SELECT COUNT(*) AS count FROM transactions WHERE from_account = ?', [id])).count, 0);
    assert.equal((await store.get(bank.db, 'SELECT COUNT(*) AS count FROM mobile_transfers WHERE sender_id = ?', [id])).count, 0);
  } finally {
    await store.run(bank.db, 'DROP TRIGGER reject_test_debit');
  }
});

test('concurrent mobile payments cannot spend the same available funds twice', async () => {
  const customer = await signup();
  const responses = await Promise.all([1, 2].map(() => api('/api/mobile-transfers', {
    method: 'POST', cookie: customer.cookie, body: payment({ amount: '3000' })
  })));
  assert.deepEqual(responses.map(response => response.status).sort(), [201, 400]);
  assert.equal((await store.get(bank.db, 'SELECT balance FROM users WHERE id = ?', [customer.data.user.id])).balance, 2000);
});

test('legacy SQL injection, IDOR, unverified role claims, and plaintext exposure remain available', async () => {
  const bypass = await login("' OR '1'='1' -- ", 'not_the_password');
  assert.equal(bypass.data.user.id, 1);
  const customer = await signup();
  assert.equal((await api('/api/account/3', { cookie: customer.cookie })).data.account.username, 'admin');
  const header = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({ id: customer.data.user.id, username: customer.credentials.username, is_admin: true })).toString('base64url');
  const forgedCookie = `token=${header}.${payload}.`;
  const exposed = await api('/api/admin/users', { cookie: forgedCookie });
  assert.equal(exposed.status, 200);
  assert.equal(exposed.data.users.find(user => user.username === 'admin').password, 'admin');
  const other = await signup();
  assert.equal((await api(`/api/admin/users/${other.data.user.id}/role`, {
    method: 'PATCH', cookie: forgedCookie, body: { role: 'admin' }
  })).status, 200);
  const search = "%' UNION SELECT id, username, password, full_name, balance, is_admin FROM users -- ";
  const union = await api(`/api/transactions?search=${encodeURIComponent(search)}`, { cookie: customer.cookie });
  assert.equal(union.status, 200);
  assert.ok(union.data.transactions.some(row => row.from_account === 'admin' && row.to_account === 'admin'));
});

test('legacy negative transfers, raw HTML, verbose errors, traversal, and insecure cookies remain', async () => {
  const customer = await signup();
  const negative = await api('/api/transfer', {
    method: 'POST', cookie: customer.cookie, body: { to_account: 2, amount: '-1.25', note: 'Legacy lab check' }
  });
  assert.equal(negative.status, 200);
  const marker = '<script>window.labMarker = 1</script>';
  assert.equal((await api('/api/comments', {
    method: 'POST', cookie: customer.cookie, body: { account_id: 3, body: marker }
  })).status, 200);
  assert.ok((await api('/api/comments/3')).data.comments.some(comment => comment.body === marker));
  assert.ok((await api(`/api/search-help?q=${encodeURIComponent(marker)}`)).text.includes(marker));
  const sqlError = await api(`/api/transactions?search=${encodeURIComponent("'")}`, { cookie: customer.cookie });
  assert.equal(sqlError.status, 500);
  assert.match(sqlError.text, /SQLITE_ERROR/);
  const traversal = await api(`/api/statement?file=${encodeURIComponent('../package.json')}`, { cookie: customer.cookie });
  assert.equal(JSON.parse(traversal.text).name, 'vuln-bank');
  assert.ok(customer.cookies.length >= 2);
  assert.ok(customer.cookies.every(cookie => !/HttpOnly|Secure|SameSite/i.test(cookie)));
});
