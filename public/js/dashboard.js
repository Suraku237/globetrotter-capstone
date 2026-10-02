// dashboard.js
async function loadAccount(id) {
  const res = await fetch(`/api/account/${id}`);
  const data = await res.json();
  if (data.success) {
    document.getElementById('fullName').textContent = data.account.full_name;
    document.getElementById('balance').textContent = Number(data.account.balance).toFixed(2);
    document.getElementById('accountId').textContent = data.account.id;
  }
}

async function loadTransactions() {
  const search = document.getElementById('searchBox').value;
  const res = await fetch(`/api/transactions?search=${encodeURIComponent(search)}`);

  // The search box intentionally allows SQLi payloads that can break query syntax
  // (see server.js VULNERABILITY: SQL Injection). When that happens the server
  // returns a raw HTML/SQL error instead of JSON — surface it instead of throwing.
  const contentType = res.headers.get('content-type') || '';
  const tbody = document.querySelector('#txTable tbody');
  if (!contentType.includes('application/json')) {
    const text = await res.text();
    tbody.innerHTML = `<tr><td colspan="5"><pre style="white-space:pre-wrap;color:#eb2f06">${text}</pre></td></tr>`;
    return;
  }

  const data = await res.json();
  tbody.innerHTML = '';
  if (data.success) {
    data.transactions.forEach(tx => {
      const row = document.createElement('tr');
      row.innerHTML = `<td>${tx.from_account ?? ''}</td><td>${tx.to_account ?? ''}</td><td>$${tx.amount ?? ''}</td><td>${tx.note ?? ''}</td><td>${tx.created_at ?? ''}</td>`;
      tbody.appendChild(row);
    });
  }
}

(async () => {
  const user = await requirePageAuth();
  if (user) {
    await loadAccount(user.id);
    await loadTransactions();
  }
})();
