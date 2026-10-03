let transferUser;
let selectedProvider = 'mtn';
const providerNames = { mtn: 'MTN MoMo', orange: 'Orange Money' };
const mobileForm = document.getElementById('mobileTransferForm');
const mobileFields = document.getElementById('mobileFields');
const mobileSubmit = document.getElementById('mobileSubmit');

function selectProvider(provider) {
  selectedProvider = provider;
  document.querySelectorAll('[data-provider]').forEach(button => {
    button.setAttribute('aria-pressed', String(button.dataset.provider === provider));
  });
  document.getElementById('selectedProvider').textContent = providerNames[provider];
  mobileSubmit.textContent = `Send with ${providerNames[provider]}`;
}

document.querySelectorAll('[data-provider]').forEach(button => {
  button.addEventListener('click', () => selectProvider(button.dataset.provider));
});

async function loadTransferBalance() {
  const res = await fetch(`/api/account/${transferUser.id}`);
  const data = await readJsonResponse(res, 'pageError');
  if (!data) return false;
  if (!res.ok || !data.success) {
    showStatus('pageError', data.message || 'Unable to load the account balance.');
    return false;
  }
  document.getElementById('transferBalance').textContent = formatMoney(data.account.balance);
  return true;
}

mobileForm.addEventListener('submit', async event => {
  event.preventDefault();
  showStatus('mobileMsg', '');
  mobileFields.disabled = true;
  mobileSubmit.textContent = 'Processing simulated transfer...';
  try {
    const res = await fetch('/api/mobile-transfers', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        provider: selectedProvider,
        phone_number: document.getElementById('mobilePhone').value,
        amount: document.getElementById('mobileAmount').value,
        pin: document.getElementById('mobilePin').value,
        note: document.getElementById('mobileNote').value
      })
    });
    const data = await readJsonResponse(res, 'mobileMsg');
    if (!data) return;
    if (!res.ok || !data.success) {
      showStatus('mobileMsg', data.message || 'The simulated transfer failed.');
      return;
    }
    const transfer = data.transfer;
    document.getElementById('transferBalance').textContent = formatMoney(data.balance);
    document.getElementById('receiptMessage').textContent = data.message;
    document.getElementById('receiptReference').textContent = transfer.reference;
    document.getElementById('receiptNetwork').textContent = transfer.provider_name;
    document.getElementById('receiptPhone').textContent = transfer.recipient_phone;
    document.getElementById('receiptAmount').textContent = formatMoney(transfer.amount);
    document.getElementById('receiptDate').textContent = `${transfer.created_at} UTC`;
    mobileForm.hidden = true;
    const receipt = document.getElementById('transferReceipt');
    receipt.hidden = false;
    receipt.focus();
    await loadMobileHistory();
  } catch (err) {
    showStatus('mobileMsg', 'Unable to send the simulated transfer: ' + err.message);
  } finally {
    document.getElementById('mobilePin').value = '';
    mobileFields.disabled = false;
    mobileSubmit.textContent = `Send with ${providerNames[selectedProvider]}`;
  }
});

document.getElementById('newTransferButton').addEventListener('click', () => {
  mobileForm.reset();
  mobileForm.hidden = false;
  document.getElementById('transferReceipt').hidden = true;
  showStatus('mobileMsg', '');
  selectProvider(selectedProvider);
  document.getElementById('mobilePhone').focus();
});

document.getElementById('transferForm').addEventListener('submit', async event => {
  event.preventDefault();
  const submit = document.getElementById('legacySubmit');
  submit.disabled = true;
  showStatus('transferMsg', '');
  try {
    const res = await fetch('/api/transfer', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        to_account: document.getElementById('toAccount').value,
        amount: document.getElementById('amount').value,
        note: document.getElementById('note').value
      })
    });
    const data = await readJsonResponse(res, 'transferMsg');
    if (!data) return;
    showStatus('transferMsg', data.message || (data.success ? 'Done' : 'Failed'), data.success ? 'success' : 'error');
    if (data.success) await loadTransferBalance();
  } catch (err) {
    showStatus('transferMsg', 'Unable to send the lab transfer: ' + err.message);
  } finally {
    submit.disabled = false;
  }
});

(async () => {
  transferUser = await requirePageAuth();
  if (!transferUser) return;
  const requested = new URLSearchParams(window.location.search).get('provider');
  if (requested && !Object.hasOwn(providerNames, requested)) {
    showStatus('mobileMsg', 'Unknown network in the link. Choose MTN MoMo or Orange Money.');
  } else {
    selectProvider(requested || 'mtn');
  }
  document.getElementById('legacySubmit').disabled = false;
  try {
    if (await loadTransferBalance()) mobileFields.disabled = false;
    await loadMobileHistory();
  } catch (err) {
    showStatus('pageError', 'Unable to prepare the transfer form: ' + err.message);
  }
})();
