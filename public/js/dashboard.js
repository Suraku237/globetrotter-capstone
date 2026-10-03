// dashboard.js
async function loadAccount(id) {
  try {
    const res = await fetch(`/api/account/${id}`);
    const data = await readJsonResponse(res, 'pageError');
    if (!data) return;
    if (!res.ok || !data.success) {
      showStatus('pageError', data.message || 'Unable to load the account.');
      return;
    }
    document.getElementById('fullName').textContent = data.account.full_name;
    document.getElementById('balance').textContent = Number(data.account.balance).toFixed(2);
    document.getElementById('accountId').textContent = data.account.id;
  } catch (err) {
    showStatus('pageError', 'Unable to load the account: ' + err.message);
  }
}

async function loadTransactions() {
  try {
    const search = document.getElementById('searchBox').value;
    const res = await fetch(`/api/transactions?search=${encodeURIComponent(search)}`);
    const contentType = res.headers.get('content-type') || '';
    const tbody = document.querySelector('#txTable tbody');
    if (!contentType.includes('application/json')) {
      const text = await res.text();
      tbody.innerHTML = `<tr><td colspan="5"><pre style="white-space:pre-wrap;color:#eb2f06">${text}</pre></td></tr>`;
      return;
    }
    const data = await res.json();
    if (!res.ok || !data.success) {
      showStatus('pageError', data.message || 'Unable to load transactions.');
      return;
    }
    tbody.innerHTML = '';
    data.transactions.forEach(tx => {
      const row = document.createElement('tr');
      // Raw transaction fields remain intentional for the existing injection exercises.
      row.innerHTML = `<td>${tx.from_account ?? ''}</td><td>${tx.to_account ?? ''}</td><td>${tx.amount ?? ''} FCFA</td><td>${tx.note ?? ''}</td><td>${tx.created_at ?? ''}</td>`;
      tbody.appendChild(row);
    });
  } catch (err) {
    showStatus('pageError', 'Unable to load transactions: ' + err.message);
  }
}

(async () => {
  const user = await requirePageAuth();
  if (user) {
    const query = new URLSearchParams(window.location.search);
    if (query.get('welcome') === '1') {
      showStatus('dashboardNotice', 'Your demo account is ready with 5,000 FCFA of simulated starter funds.', 'success');
    } else if (query.get('notice') === 'admin') {
      showStatus('dashboardNotice', 'The admin workspace requires an administrator role.', 'info');
    }
    await Promise.all([loadAccount(user.id), loadTransactions(), loadMobileHistory()]);
  }
})();
