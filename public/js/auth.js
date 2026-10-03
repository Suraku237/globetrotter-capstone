// Shared session, status, and simulated-payment display helpers.

function showStatus(target, message, kind = 'error') {
  const element = typeof target === 'string' ? document.getElementById(target) : target;
  if (!element) {
    console.error('Missing status element:', target, message);
    return;
  }
  element.className = `status ${kind}`;
  element.textContent = message;
  element.hidden = !message;
}

async function readJsonResponse(response, target) {
  if (!(response.headers.get('content-type') || '').includes('application/json')) {
    const element = typeof target === 'string' ? document.getElementById(target) : target;
    const text = await response.text();
    // Intentionally retain raw error HTML for the existing verbose-error/XSS labs.
    element.className = 'status error';
    element.hidden = false;
    element.innerHTML = `<pre>${text}</pre>`;
    return null;
  }
  return response.json();
}

function formatMoney(value) {
  return `${Number(value).toFixed(2)} FCFA`;
}

async function requirePageAuth(adminOnly = false) {
  try {
    const res = await fetch('/api/whoami');
    if (res.status === 401) {
      window.location.replace('index.html');
      return null;
    }
    const data = await readJsonResponse(res, 'pageError');
    if (!data) return null;
    if (!res.ok || !data.success || !data.user || typeof data.user !== 'object') {
      showStatus('pageError', data.message || 'Unable to verify this lab session. Sign in again.');
      return null;
    }
    const user = data.user;
    if (adminOnly && !user.is_admin) {
      window.location.replace('dashboard.html?notice=admin');
      return null;
    }
    // Navigation follows the intentionally weak token claims; it is not a security boundary.
    document.querySelectorAll('[data-admin-only]').forEach(link => { link.hidden = !user.is_admin; });
    document.querySelectorAll('[data-user-name]').forEach(element => { element.textContent = user.username; });
    document.querySelectorAll('[data-user-role]').forEach(element => { element.textContent = user.is_admin ? 'Administrator' : 'User'; });
    document.querySelectorAll('[data-user-initial]').forEach(element => { element.textContent = String(user.username || 'V').charAt(0).toUpperCase(); });
    return user;
  } catch (e) {
    showStatus('pageError', 'Unable to check your session: ' + e.message);
    return null;
  }
}

function wireLogoutLink() {
  const logoutLink = document.getElementById('logoutLink');
  if (!logoutLink) return;
  logoutLink.addEventListener('click', async (e) => {
    e.preventDefault();
    try {
      const res = await fetch('/api/logout', { method: 'POST' });
      const data = await readJsonResponse(res, 'pageError');
      if (!data) return;
      if (!res.ok || !data.success) {
        showStatus('pageError', data.message || 'Sign out failed. Try again.');
        return;
      }
      localStorage.removeItem('currentUserId');
      window.location.href = 'index.html';
    } catch (err) {
      showStatus('pageError', 'Unable to sign out: ' + err.message);
    }
  });
}

async function loadMobileHistory() {
  const container = document.getElementById('mobileHistory');
  try {
    const res = await fetch('/api/mobile-transfers');
    const data = await readJsonResponse(res, container);
    if (!data) return;
    if (!res.ok || !data.success) {
      showStatus(container, data.message || 'Unable to load mobile payments.');
      return;
    }
    container.className = '';
    container.hidden = false;
    container.replaceChildren();
    if (!data.transfers.length) {
      const empty = document.createElement('p');
      empty.className = 'empty-state';
      empty.textContent = 'No mobile payments yet. Your simulated transfers will appear here.';
      container.appendChild(empty);
      return;
    }
    data.transfers.forEach(transfer => {
      const row = document.createElement('article');
      row.className = 'payment-row';
      row.innerHTML = '<div class="payment-details"><strong data-phone></strong><div class="payment-meta"><span data-network></span><span data-reference></span></div></div><div class="payment-amount"><strong data-amount></strong><small data-date></small></div>';
      row.querySelector('[data-phone]').textContent = transfer.recipient_phone;
      const network = row.querySelector('[data-network]');
      network.className = `network-tag ${transfer.provider}`;
      network.textContent = transfer.provider_name;
      row.querySelector('[data-reference]').textContent = transfer.reference;
      row.querySelector('[data-amount]').textContent = formatMoney(transfer.amount);
      row.querySelector('[data-date]').textContent = `${transfer.created_at} UTC - simulated`;
      container.appendChild(row);
    });
  } catch (err) {
    showStatus(container, 'Unable to load mobile payments: ' + err.message);
  }
}

wireLogoutLink();
