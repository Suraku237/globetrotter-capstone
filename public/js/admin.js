// admin.js
requirePageAuth();

async function loadUsers() {
  const res = await fetch('/api/admin/users');
  const data = await res.json();
  const tbody = document.querySelector('#userTable tbody');
  tbody.innerHTML = '';
  document.getElementById('adminMsg').textContent = '';
  if (data.success) {
    data.users.forEach(u => {
      const row = document.createElement('tr');
      row.innerHTML = `<td>${u.id}</td><td>${u.username}</td><td>${u.password}</td><td>${u.full_name}</td><td>$${u.balance}</td><td>${u.is_admin ? 'Yes' : 'No'}</td>`;
      tbody.appendChild(row);
    });
  } else {
    document.getElementById('adminMsg').textContent = data.message || 'Forbidden';
  }
}
