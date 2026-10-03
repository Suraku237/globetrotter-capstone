// login.js
const togglePasswordBtn = document.getElementById('togglePassword');
const passwordInput = document.getElementById('password');
togglePasswordBtn.addEventListener('click', () => {
  const isHidden = passwordInput.type === 'password';
  passwordInput.type = isHidden ? 'text' : 'password';
  togglePasswordBtn.textContent = isHidden ? 'Hide' : 'Show';
  togglePasswordBtn.setAttribute('aria-label', isHidden ? 'Hide password' : 'Show password');
});

document.getElementById('loginForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const username = document.getElementById('username').value;
  const password = document.getElementById('password').value;
  const errorMsg = document.getElementById('errorMsg');
  const submit = document.getElementById('loginSubmit');
  showStatus(errorMsg, '');
  submit.disabled = true;
  submit.textContent = 'Signing in...';

  try {
    const res = await fetch('/api/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password })
    });

    const data = await readJsonResponse(res, errorMsg);
    if (!data) return;
    if (res.ok && data.success) {
      localStorage.setItem('currentUserId', data.user.id);
      window.location.href = data.user.is_admin ? 'admin.html' : 'dashboard.html';
    } else {
      showStatus(errorMsg, data.message || 'Login failed');
    }
  } catch (err) {
    showStatus(errorMsg, 'Error contacting server: ' + err.message);
  } finally {
    submit.disabled = false;
    submit.textContent = 'Sign In';
  }
});
