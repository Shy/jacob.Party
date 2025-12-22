// Service Worker for Push Notifications
// jacob.party test

self.addEventListener('install', (event) => {
    console.log('Service Worker installing...');
    self.skipWaiting();
});

self.addEventListener('activate', (event) => {
    console.log('Service Worker activated');
    event.waitUntil(clients.claim());
});

// Handle push events
self.addEventListener('push', (event) => {
    console.log('Push notification received:', event);

    let data = {
        title: 'jason.party',
        body: 'Party event notification',
        icon: '/icon.png',
        badge: '/badge.png',
        data: { url: self.location.origin }
    };

    // Parse push data if available
    if (event.data) {
        try {
            data = event.data.json();
        } catch (e) {
            data.body = event.data.text();
        }
    }

    const options = {
        body: data.body,
        icon: data.icon || '/icon.png',
        badge: data.badge || '/badge.png',
        data: data.data || {},
        vibrate: [200, 100, 200],
        tag: 'party-notification',
        requireInteraction: false
    };

    event.waitUntil(
        self.registration.showNotification(data.title, options)
    );
});

// Handle notification clicks
self.addEventListener('notificationclick', (event) => {
    console.log('Notification clicked:', event);

    event.notification.close();

    const urlToOpen = event.notification.data?.url || self.location.origin;

    event.waitUntil(
        clients.matchAll({ type: 'window', includeUncontrolled: true })
            .then((clientList) => {
                // Focus existing window if found
                for (const client of clientList) {
                    if (client.url === urlToOpen && 'focus' in client) {
                        return client.focus();
                    }
                }
                // Open new window if no existing window found
                if (clients.openWindow) {
                    return clients.openWindow(urlToOpen);
                }
            })
    );
});

// Handle push subscription change (e.g., subscription expired)
self.addEventListener('pushsubscriptionchange', (event) => {
    console.log('Push subscription changed:', event);

    event.waitUntil(
        self.registration.pushManager.subscribe({
            userVisibleOnly: true,
            applicationServerKey: event.oldSubscription.options.applicationServerKey
        }).then((subscription) => {
            // Send new subscription to server
            return fetch('/api/subscribe', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    id: crypto.randomUUID(),
                    endpoint: subscription.endpoint,
                    authKey: btoa(String.fromCharCode(...new Uint8Array(subscription.getKey('auth')))),
                    p256dhKey: btoa(String.fromCharCode(...new Uint8Array(subscription.getKey('p256dh')))),
                    createdAt: new Date().toISOString()
                })
            });
        })
    );
});
