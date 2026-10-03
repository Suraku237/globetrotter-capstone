document.getElementById('signupForm').addEventListener('submit', async event => {
  event.preventDefault();
  const password = document.getElementById('signupPassword').value;
  showStatus('signupMsg', '');
  if (password !== document.getElementById('confirmPassword').value) {
    showStatus('signupMsg', 'The passwords do not match.');
    return;
  }
  const submit = document.getElementById('signupSubmit');
  submit.disabled = true;
  submit.textContent = 'Creating your account...';
  try {
    const res = await fetch('/api/signup', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        full_name: document.getElementById('fullName').value,
        username: document.getElementById('signupUsername').value,
        phone_number: document.getElementById('signupPhone').value,
        password,
        pin: document.getElementById('signupPin').value
      })
    });
    const data = await readJsonResponse(res, 'signupMsg');
    if (!data) return;
    if (!res.ok || !data.success) {
      showStatus('signupMsg', data.message || 'Unable to create the demo account.');
      return;
    }
    localStorage.setItem('currentUserId', data.user.id);
    window.location.href = 'dashboard.html?welcome=1';
  } catch (err) {
    showStatus('signupMsg', 'Unable to create the account: ' + err.message);
  } finally {
    submit.disabled = false;
    submit.textContent = 'Create demo account';
  }
});
