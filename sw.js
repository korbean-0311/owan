/* 오운완 서비스워커 — 앱 셸 캐시 (오프라인/설치용) */
const CACHE = 'owan-v1';
const SHELL = ['./index.html', './supabase-config.js', './icon.svg', './manifest.json'];

self.addEventListener('install', function(e){
  e.waitUntil(caches.open(CACHE).then(function(c){ return c.addAll(SHELL); }).then(function(){ return self.skipWaiting(); }));
});
self.addEventListener('activate', function(e){
  e.waitUntil(caches.keys().then(function(ks){
    return Promise.all(ks.filter(function(k){ return k!==CACHE; }).map(function(k){ return caches.delete(k); }));
  }).then(function(){ return self.clients.claim(); }));
});
self.addEventListener('fetch', function(e){
  var req = e.request;
  if(req.method !== 'GET') return;
  var url = new URL(req.url);
  if(url.origin !== location.origin) return;          // Supabase/CDN 등 외부는 항상 네트워크
  if(req.mode === 'navigate'){                          // 페이지 이동: 네트워크 우선, 실패 시 캐시
    e.respondWith(fetch(req).catch(function(){ return caches.match('./index.html'); }));
    return;
  }
  e.respondWith(caches.match(req).then(function(c){ return c || fetch(req); }));
});
