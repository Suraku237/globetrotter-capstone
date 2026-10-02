// transfer.js
requirePageAuth();

document.getElementById('transferForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const to_account = document.getElementById('toAccount').value;
  const amount = document.getElementById('amount').value;
  const note = document.getElementById('note').value;

  const res = await fetch('/api/transfer', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ to_account, amount, note })
  });
  const data = await res.json();
  document.getElementById('transferMsg').textContent = data.message || (data.success ? 'Done' : 'Failed');
});
