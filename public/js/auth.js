// auth.js — shared across all protected pages (Dashboard, Account, Transfer, Tools, Admin).
// Ensures every page consistently: (1) verifies the user is logged in, redirecting to the
// login page otherwise, and (2) wires up the Logout link if present on the page.

async function requirePageAuth() {
  try {
    const res = await fetch('/api/whoami');
    if (res.status !== 200) {
      window.location.href = 'index.html';
      return null;
    }
    const data = await res.json();
    return data.user;
  } catch (e) {
    window.location.href = 'index.html';
    return null;
  }
}

function wireLogoutLink() {
  const logoutLink = document.getElementById('logoutLink');
  if (!logoutLink) return;
  logoutLink.addEventListener('click', async (e) => {
    e.preventDefault();
    await fetch('/api/logout', { method: 'POST' });
    window.location.href = 'index.html';
  });
}

// Automatically wire the logout link (if present) as soon as this script loads.
// Individual page scripts are responsible for calling requirePageAuth() themselves
// so they can control the order of operations (e.g. load account data afterward).
wireLogoutLink();
