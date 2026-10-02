// tools.js
requirePageAuth();

async function doPing() {
  const host = document.getElementById('hostInput').value;
  const res = await fetch('/api/ping', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ host })
  });
  const data = await res.json();
  document.getElementById('pingResult').textContent = data.output || 'No output';
}

async function getStatement() {
  const file = document.getElementById('fileInput').value;
  const res = await fetch(`/api/statement?file=${encodeURIComponent(file)}`);
  const text = await res.text();
  document.getElementById('statementResult').textContent = text;
}

function openHelp() {
  const q = document.getElementById('helpQuery').value;
  window.open(`/api/search-help?q=${encodeURIComponent(q)}`, '_blank');
}
