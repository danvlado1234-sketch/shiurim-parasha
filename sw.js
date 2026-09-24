// ============================================================
//  Service Worker של אפליקציית הפרשות
//  מה שהוא עושה: מאפשר להתקין את האתר כאפליקציה, ולפתוח אותו גם
//  בלי אינטרנט (הדף, הרשימה, התמונות והגופנים שכבר נטענו פעם).
//  - הדף ורשימות ה-JSON: קודם מהרשת (תמיד הגרסה העדכנית), ורק אם אין
//    רשת - מהעותק השמור. לכן עדכון של index.html/list.json מופיע מיד.
//  - תמונות, אייקונים וגופנים: מהעותק השמור, ומתעדכנים ברקע.
//  - קובצי השמע והסיכומים (R2) לא עוברים כאן בכלל - ישר לרשת.
//  המשניות יושבות באותה כתובת אבל בתיקייה אחרת - ה-SW הזה חל רק על
//  /shiurim-parasha/ ולא נוגע בהן.
// ============================================================
const CACHE = 'parasha-v2';
const CORE = ['./', 'index.html', 'manifest.webmanifest', 'bg-rabbi.jpg',
  'icons/icon-192.png', 'icons/icon-512.png', 'icons/apple-touch-icon.png', 'icons/favicon-32.png'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(CORE)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys()
    .then(keys => Promise.all(keys.filter(k => k.startsWith('parasha-') && k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

// מפתח קבוע לקבצים שנטענים עם ?t=... נגד מטמון (list.json?t=123 -> list.json)
function cacheKey(req){
  const url = new URL(req.url);
  if (url.origin === self.location.origin) url.search = '';
  return url.href;
}

async function networkFirst(req){
  const cache = await caches.open(CACHE);
  try {
    const res = await fetch(req);
    if (res.ok) cache.put(cacheKey(req), res.clone());
    return res;
  } catch (err) {
    const hit = await cache.match(cacheKey(req)) || (req.mode === 'navigate' && await cache.match('./'));
    if (hit) return hit;
    throw err;
  }
}

async function cacheFirst(req){
  const cache = await caches.open(CACHE);
  const hit = await cache.match(req);
  const refresh = fetch(req).then(res => { if (res.ok || res.type === 'opaque') cache.put(req, res.clone()); return res; });
  if (hit){ refresh.catch(() => {}); return hit; }
  return refresh;
}

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  const sameOrigin = url.origin === self.location.origin;
  if (req.mode === 'navigate' || (sameOrigin && /\.(json|html)$|\/$/.test(url.pathname))){
    e.respondWith(networkFirst(req));
  } else if (sameOrigin || url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com'){
    e.respondWith(cacheFirst(req));
  }
  // כל השאר (קובצי השמע וה-PDF בענן) - בלי התערבות
});
