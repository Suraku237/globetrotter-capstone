let adminUser;

async function loadUsers() {
  if (!adminUser) return;
  const loadButton = document.getElementById('loadUsersButton');
  loadButton.disabled = true;
  showStatus('adminMsg', '');
  try {
    const res = await fetch('/api/admin/users');
    const data = await readJsonResponse(res, 'adminMsg');
    if (!data) return;
    if (!res.ok || !data.success) {
      showStatus('adminMsg', data.message || 'Forbidden');
      return;
    }
    const tbody = document.querySelector('#userTable tbody');
    tbody.innerHTML = '';
    document.getElementById('customerCount').textContent = data.users.length;
    document.getElementById('adminCount').textContent = data.users.filter(user => user.is_admin).length;
    document.getElementById('totalFunds').textContent = formatMoney(data.users.reduce((sum, user) => sum + Number(user.balance), 0));
    data.users.forEach(u => {
      const row = document.createElement('tr');
      // Keep the lab's plaintext password exposure and raw user-field rendering.
      row.innerHTML = `<td>${u.id}</td><td><a href="account.html?id=${u.id}">${u.full_name}</a></td><td>${u.username}</td><td>${u.phone_number ?? 'Not set'}</td><td class="password-cell">${u.password}</td><td>${u.balance} FCFA</td>`;
      const roleCell = document.createElement('td');
      const select = document.createElement('select');
      select.className = 'role-select';
      select.setAttribute('aria-label', `Role for ${u.username}`);
      select.innerHTML = '<option value="user">User</option><option value="admin">Admin</option>';
      const originalRole = u.is_admin ? 'admin' : 'user';
      select.value = originalRole;
      select.disabled = u.id === adminUser.id;
      roleCell.appendChild(select);
      const actionCell = document.createElement('td');
      const save = document.createElement('button');
      save.type = 'button';
      save.className = 'role-save';
      save.textContent = u.id === adminUser.id ? 'Your account' : 'Save role';
      save.disabled = true;
      select.addEventListener('change', () => {
        save.disabled = select.disabled || select.value === originalRole;
      });
      save.addEventListener('click', async () => {
        save.disabled = true;
        select.disabled = true;
        try {
          const response = await fetch(`/api/admin/users/${u.id}/role`, {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ role: select.value })
          });
          const result = await readJsonResponse(response, 'adminMsg');
          if (!result) return;
          if (!response.ok || !result.success) {
            showStatus('adminMsg', result.message || 'Unable to change this role.');
            return;
          }
          await loadUsers();
          showStatus('adminMsg', result.message, 'success');
        } catch (err) {
          showStatus('adminMsg', 'Unable to update the role: ' + err.message);
        } finally {
          select.disabled = u.id === adminUser.id;
          save.disabled = select.disabled || select.value === originalRole;
        }
      });
      actionCell.appendChild(save);
      row.appendChild(roleCell);
      row.appendChild(actionCell);
      tbody.appendChild(row);
    });
  } catch (err) {
    showStatus('adminMsg', 'Unable to load users: ' + err.message);
  } finally {
    loadButton.disabled = false;
  }
}

(async () => {
  adminUser = await requirePageAuth(true);
  if (adminUser) await loadUsers();
})();
