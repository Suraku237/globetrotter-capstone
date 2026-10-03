// account.js
// VULNERABILITY (frontend contributing factor): comments are inserted via innerHTML without
// escaping, enabling stored XSS payloads saved through /api/comments to execute here.

let currentAccId = 1;

async function loadProfile() {
  try {
    currentAccId = document.getElementById('accIdInput').value;
    const res = await fetch(`/api/account/${currentAccId}`);
    const el = document.getElementById('profileResult');
    const contentType = res.headers.get('content-type') || '';
    if (!contentType.includes('application/json')) {
      el.innerHTML = `<pre style="white-space:pre-wrap;color:#eb2f06">${await res.text()}</pre>`;
      return;
    }
    const data = await res.json();
    if (data.success) {
      el.innerHTML = `<h3>${data.account.full_name}</h3><div class="profile-balance">${data.account.balance} FCFA</div><div class="profile-meta">Username: ${data.account.username}<br>Account ID: ${data.account.id}<br>Phone: ${data.account.phone_number ?? 'Not set'}<br>Role: ${data.account.is_admin ? 'Administrator' : 'User'}</div>`;
    } else {
      el.textContent = data.message || 'Not found';
    }
    await loadComments();
  } catch (err) {
    showStatus('pageError', 'Unable to load the profile: ' + err.message);
  }
}

async function loadComments() {
  try {
    const res = await fetch(`/api/comments/${currentAccId}`);
    const data = await readJsonResponse(res, 'commentMsg');
    if (!data) return;
    if (!res.ok || !data.success) {
      showStatus('commentMsg', data.message || 'Unable to load notes.');
      return;
    }
    const list = document.getElementById('commentsList');
    list.innerHTML = '';
    data.comments.forEach(c => {
      const div = document.createElement('div');
      div.className = 'comment';
      // Intentionally vulnerable: using innerHTML with raw, unsanitized user content.
      div.innerHTML = `<b>${c.author}:</b> ${c.body}`;
      list.appendChild(div);
    });
  } catch (err) {
    showStatus('commentMsg', 'Unable to load notes: ' + err.message);
  }
}

async function postComment() {
  showStatus('commentMsg', '');
  try {
    const body = document.getElementById('commentBody').value;
    const res = await fetch('/api/comments', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ account_id: currentAccId, body })
    });
    const data = await readJsonResponse(res, 'commentMsg');
    if (!data) return;
    if (!res.ok || !data.success) {
      showStatus('commentMsg', data.message || 'Unable to post the note.');
      return;
    }
    document.getElementById('commentBody').value = '';
    await loadComments();
  } catch (err) {
    showStatus('commentMsg', 'Unable to post the note: ' + err.message);
  }
}

(async () => {
  const user = await requirePageAuth();
  if (user) {
    const requested = new URLSearchParams(window.location.search).get('id');
    document.getElementById('accIdInput').value = requested === null ? user.id : requested;
    await loadProfile();
  }
})();
