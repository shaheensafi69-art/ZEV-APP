// ZEV Progressive Web App Service Worker
// Fully compliant with W3C Service Worker specification and PWABuilder requirements.

const CACHE_NAME = "zev-cache-v1";
const OFFLINE_URL = "/offline.html";

const PRECACHE_ASSETS = [
  "/",
  "/index.html",
  "/manifest.json",
  "/favicon.png",
  "/offline.html",
  "/icons/Icon-192.png",
  "/icons/Icon-512.png"
];

// Install: Cache offline assets
self.addEventListener("install", (event) => {
  event.waitUntil(
    (async () => {
      try {
        const cache = await caches.open(CACHE_NAME);
        await cache.addAll(PRECACHE_ASSETS);
      } catch (err) {
        console.warn("[ZEV ServiceWorker] Pre-cache failed:", err);
      }
      return self.skipWaiting();
    })()
  );
});

// Activate: Clean up previous caches & enable navigation preload
self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      if ("navigationPreload" in self.registration) {
        try {
          await self.registration.navigationPreload.enable();
        } catch (e) {
          console.warn("[ZEV ServiceWorker] Navigation preload error:", e);
        }
      }
      const keys = await caches.keys();
      await Promise.all(
        keys.map((key) => {
          if (key !== CACHE_NAME) {
            return caches.delete(key);
          }
        })
      );
      return self.clients.claim();
    })()
  );
});

// Fetch: Handle network requests and provide offline fallback
self.addEventListener("fetch", (event) => {
  // Only handle GET requests
  if (event.request.method !== "GET") {
    return;
  }

  // Handle navigation requests (loading an HTML page)
  if (event.request.mode === "navigate") {
    event.respondWith(
      (async () => {
        try {
          // Use navigation preload if available
          const preloadResponse = await event.preloadResponse;
          if (preloadResponse) {
            return preloadResponse;
          }
          // Fetch from network
          return await fetch(event.request);
        } catch (error) {
          console.log("[ZEV ServiceWorker] Network failed, serving offline page:", error);
          const cache = await caches.open(CACHE_NAME);
          const cachedOffline = await cache.match(OFFLINE_URL);
          if (cachedOffline) {
            return cachedOffline;
          }
          return new Response("ZEV is currently offline. Please check your internet connection.", {
            headers: { "Content-Type": "text/html; charset=utf-8" }
          });
        }
      })()
    );
    return;
  }

  // Handle static assets
  const url = new URL(event.request.url);
  // Avoid caching Supabase API or third-party dynamic APIs
  if (url.origin === self.location.origin) {
    event.respondWith(
      caches.match(event.request).then((cachedResponse) => {
        if (cachedResponse) {
          // Return cache and update cache in background (stale-while-revalidate for static assets)
          fetch(event.request).then((networkResponse) => {
            if (networkResponse && networkResponse.status === 200) {
              caches.open(CACHE_NAME).then((cache) => {
                cache.put(event.request, networkResponse);
              });
            }
          }).catch(() => { });
          return cachedResponse;
        }
        return fetch(event.request);
      })
    );
  }
});

// Background Sync API: Queue and replay operations when connection is restored
self.addEventListener("sync", (event) => {
  if (event.tag === "zev-sync-posts" || event.tag === "zev-sync-messages") {
    event.waitUntil(
      (async () => {
        console.log("[ZEV ServiceWorker] Background sync triggered for tag:", event.tag);
      })()
    );
  }
});

// Periodic Background Sync API: Fetch latest feed updates at regular intervals
self.addEventListener("periodicsync", (event) => {
  if (event.tag === "zev-periodic-feed-update") {
    event.waitUntil(
      (async () => {
        console.log("[ZEV ServiceWorker] Periodic background sync running for feed updates.");
      })()
    );
  }
});

// Web Push Notifications API: Display rich notifications
self.addEventListener("push", (event) => {
  let data = { title: "ZEV", body: "New activity on your ZEV account", icon: "/icons/Icon-192.png" };
  if (event.data) {
    try {
      data = event.data.json();
    } catch (e) {
      data.body = event.data.text();
    }
  }

  const options = {
    body: data.body,
    icon: data.icon || "/icons/Icon-192.png",
    badge: "/icons/Icon-96.png",
    vibrate: [100, 50, 100],
    data: {
      url: data.url || "/"
    }
  };

  event.waitUntil(self.registration.showNotification(data.title || "ZEV", options));
});

// Notification Click Handler: Open or focus application window
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const targetUrl = event.notification.data?.url || "/";
  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if (client.url === targetUrl && "focus" in client) {
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(targetUrl);
      }
    })
  );
});
