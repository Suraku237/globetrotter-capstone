/* Public Firebase web application identifiers, matching lib/firebase_options.dart.
   No Firebase service-account, APNs, or LiveKit server secrets belong here. */
const callIdPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function notificationCallData(notification) {
  return notification.data?.FCM_MSG?.data || notification.data;
}

function deliveryState(enabled) {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('globetrotter-call-push', 1);
    request.onupgradeneeded = () => request.result.createObjectStore('settings');
    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      const database = request.result;
      const transaction = database.transaction('settings', enabled === undefined ? 'readonly' : 'readwrite');
      const store = transaction.objectStore('settings');
      const operation = enabled === undefined ? store.get('enabled') : store.put(enabled, 'enabled');
      let value = false;
      operation.onsuccess = () => { value = enabled === undefined ? operation.result === true : enabled; };
      transaction.oncomplete = () => { database.close(); resolve(value); };
      transaction.onerror = () => { database.close(); reject(transaction.error); };
      transaction.onabort = () => { database.close(); reject(transaction.error); };
    };
  });
}

self.addEventListener('message', event => {
  if (event.data?.type !== 'call_push_enabled') return;
  event.waitUntil((async () => {
    try {
      await deliveryState(event.data.enabled === true);
      if (event.data.enabled !== true) {
        const notifications = await self.registration.getNotifications();
        notifications.filter(item => notificationCallData(item)?.type === 'incoming_call').forEach(item => item.close());
      }
      event.ports[0]?.postMessage({ok: true});
    } catch (_) {
      event.ports[0]?.postMessage({ok: false});
    }
  })());
});

// Install this before Firebase's listener so custom notification clicks navigate
// to the app without its default handler swallowing the click.
self.addEventListener('notificationclick', event => {
  const data = notificationCallData(event.notification);
  if (!data || data.type !== 'incoming_call' || !callIdPattern.test(data.call_id)) return;
  event.stopImmediatePropagation();
  event.notification.close();
  event.waitUntil((async () => {
    if (!await deliveryState()) return;
    if (!Number.isFinite(Date.parse(data.expires_at)) || Date.parse(data.expires_at) <= Date.now()) return;
    let url = new URL('./', self.location.href);
    if (typeof data.link === 'string') {
      try {
        const configured = new URL(data.link);
        if (configured.protocol === 'https:' &&
            configured.origin === url.origin &&
            !configured.username && !configured.password) {
          url = configured;
        }
      } catch (_) {
        // Invalid or cross-origin links never override the local app fallback.
      }
    }
    url.searchParams.set('call_id', data.call_id.toLowerCase());
    url.searchParams.set('call_expires_at', data.expires_at);
    const tabs = await self.clients.matchAll({type: 'window', includeUncontrolled: true});
    const tab = tabs.find(client => new URL(client.url).origin === url.origin);
    if (tab) {
      await tab.navigate(url.href);
      await tab.focus();
    } else {
      await self.clients.openWindow(url.href);
    }
  })());
});

importScripts('https://www.gstatic.com/firebasejs/11.10.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/11.10.0/firebase-messaging-compat.js');
firebase.initializeApp({
  apiKey: 'AIzaSyCi0lZznIJXCBrAoAwC8EV4vDmcKqOXbOM',
  appId: '1:347020498011:web:dea1efd2a47936cf065b7e',
  messagingSenderId: '347020498011',
  projectId: 'fast-travel-cbd10',
  authDomain: 'fast-travel-cbd10.firebaseapp.com',
});

firebase.messaging().onBackgroundMessage(async payload => {
  const data = payload.data || {};
  if (!callIdPattern.test(data.call_id || '')) return;
  const tag = `call-${data.call_id.toLowerCase()}`;
  const existing = (await self.registration.getNotifications()).filter(notification =>
    notification.tag === tag ||
    notificationCallData(notification)?.call_id?.toLowerCase() === data.call_id.toLowerCase());
  if (data.type === 'call_ended') {
    existing.forEach(notification => notification.close());
    return;
  }
  if (!await deliveryState() ||
      data.type !== 'incoming_call' ||
      !['voice', 'video'].includes(data.kind) ||
      !Number.isFinite(Date.parse(data.expires_at)) ||
      Date.parse(data.expires_at) <= Date.now()) {
    existing.forEach(notification => notification.close());
    return;
  }
  // Notification+data messages are displayed by Firebase before this callback.
  // Tolerate them without a second display; production should send data-only
  // so expiry/logout checks run before, rather than after, any system alert.
  if (payload.notification || existing.length) return;
  await self.registration.showNotification(data.caller_name || 'GlobeTrotter caller', {
    body: `Incoming ${data.kind} call. Open GlobeTrotter to answer.`,
    icon: './icons/Icon-192.png',
    tag,
    renotify: false,
    requireInteraction: true,
    data,
  });
  if (!await deliveryState()) {
    (await self.registration.getNotifications({tag})).forEach(item => item.close());
  }
});
