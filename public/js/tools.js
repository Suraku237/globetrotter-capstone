// tools.js
requirePageAuth();

async function doPing() {
  try {
    const host = document.getElementById('hostInput').value;
    const res = await fetch('/api/ping', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ host })
    });
    const data = await readJsonResponse(res, 'pageError');
    if (!data) return;
    if (!res.ok || !data.success) {
      showStatus('pageError', data.message || 'Diagnostic request failed.');
      return;
    }
    document.getElementById('pingResult').textContent = data.output || 'No output';
  } catch (err) {
    showStatus('pageError', 'Diagnostic request failed: ' + err.message);
  }
}

async function getStatement() {
  try {
    const file = document.getElementById('fileInput').value;
    const res = await fetch(`/api/statement?file=${encodeURIComponent(file)}`);
    const text = await res.text();
    document.getElementById('statementResult').textContent = text;
    if (!res.ok) showStatus('pageError', `Statement request failed (HTTP ${res.status}).`);
  } catch (err) {
    showStatus('pageError', 'Statement request failed: ' + err.message);
  }
}

function openHelp() {
  const q = document.getElementById('helpQuery').value;
  window.open(`/api/search-help?q=${encodeURIComponent(q)}`, '_blank');
}
