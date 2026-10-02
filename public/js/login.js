// login.js
const togglePasswordBtn = document.getElementById('togglePassword');
const passwordInput = document.getElementById('password');
togglePasswordBtn.addEventListener('click', () => {
  const isHidden = passwordInput.type === 'password';
  passwordInput.type = isHidden ? 'text' : 'password';
  togglePasswordBtn.textContent = isHidden ? '🙈' : '👁️';
  togglePasswordBtn.setAttribute('aria-label', isHidden ? 'Hide password' : 'Show password');
});

document.getElementById('loginForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const username = document.getElementById('username').value;
  const password = document.getElementById('password').value;
  const errorMsg = document.getElementById('errorMsg');
  errorMsg.textContent = '';

  try {
    const res = await fetch('/api/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password })
    });

    // The login endpoint intentionally returns a raw HTML/SQL error (not JSON) when a
    // malformed SQLi payload breaks the query syntax (see server.js VULNERABILITY: SQL
    // Injection). Handle that case so the real error is visible instead of a generic
    // "Error contacting server" message.
    const contentType = res.headers.get('content-type') || '';
    if (!contentType.includes('application/json')) {
      const text = await res.text();
      errorMsg.innerHTML = `<pre style="white-space:pre-wrap">${text}</pre>`;
      return;
    }

    const data = await res.json();
    if (data.success) {
      localStorage.setItem('currentUserId', data.user.id);
      window.location.href = 'dashboard.html';
    } else {
      errorMsg.textContent = data.message || 'Login failed';
    }
  } catch (err) {
    errorMsg.textContent = 'Error contacting server: ' + err.message;
  }
});
