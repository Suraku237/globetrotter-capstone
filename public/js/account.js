// account.js
// VULNERABILITY (frontend contributing factor): comments are inserted via innerHTML without
// escaping, enabling stored XSS payloads saved through /api/comments to execute here.

let currentAccId = 1;

async function loadProfile() {
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
    el.innerHTML = `<b>${data.account.full_name}</b> (user: ${data.account.username})<br>Balance: ${data.account.balance} FCFA`;
  } else {
    el.textContent = data.message || 'Not found';
  }
  await loadComments();
}

async function loadComments() {
  const res = await fetch(`/api/comments/${currentAccId}`);
  const data = await res.json();
  const list = document.getElementById('commentsList');
  list.innerHTML = '';
  if (data.success) {
    data.comments.forEach(c => {
      const div = document.createElement('div');
      div.className = 'comment';
      // Intentionally vulnerable: using innerHTML with raw, unsanitized user content.
      div.innerHTML = `<b>${c.author}:</b> ${c.body}`;
      list.appendChild(div);
    });
  }
}

async function postComment() {
  const body = document.getElementById('commentBody').value;
  await fetch('/api/comments', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ account_id: currentAccId, body })
  });
  document.getElementById('commentBody').value = '';
  await loadComments();
}

(async () => {
  const user = await requirePageAuth();
  if (user) await loadProfile();
})();
