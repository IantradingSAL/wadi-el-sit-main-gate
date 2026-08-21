// ═══════════════════════════════════════════════════════════════════════════
// wadi-municipality.js — the municipality's own details, from the database.
//
// WHY THIS FILE EXISTS
// The municipality's phone number was written into the source of five files:
//
//   citizen.html   wa.me/96176789039   ← where a FIRE REPORT is sent
//   coop.html      three places, plus the number printed in the footer
//   phonebook.html MUN_PHONE and MUN_EMAIL
//
// So changing the number the village calls in an emergency meant editing five
// files, pushing, waiting for the deploy, and hoping nobody's browser had an
// old copy. The super-admin screen has an edit form for the municipality that
// could have done it in two seconds — but the form never had a phone field,
// and no page ever read the column that was sitting there empty.
//
// A municipality that changes its number and cannot change it in its own app
// is being told to call the wrong number in a fire.
//
// HOW TO USE IT
//   <script src="wadi-municipality.js" defer></script>
//
//   WadiMun.phone()      → '+96176789039'   the main number
//   WadiMun.emergency()  → the fire/emergency number, or the main one if unset
//   WadiMun.whatsapp()   → '96176789039'    digits only, ready for wa.me
//   WadiMun.waLink(text) → 'https://wa.me/…?text=…'
//   WadiMun.email()      → the official address
//   WadiMun.name()       → 'بلدية وادي الست'
//   WadiMun.get()        → the whole record
//   WadiMun.ready        → a promise that resolves once the database answered
//
// THE ORDER IT TRIES, AND WHY
//   1. the answer from the database, once it arrives
//   2. the copy saved in localStorage from the last successful load
//   3. the built-in fallback below
//
// Step 3 is not laziness. This module is used by the fire-report button. A
// resident standing in front of a fire with no signal must still get a working
// number, so there is always one compiled in — and it is the one that was
// hardcoded before, so the worst case is exactly today's behaviour.
// KEEP THE FALLBACK IN STEP WITH THE DATABASE if the number ever changes.
// ═══════════════════════════════════════════════════════════════════════════
(function () {
  'use strict';

  var MUN_ID = '00000000-0000-0000-0000-000000000001';
  var CACHE_KEY = 'wadi_mun_v1';

  // Last resort. See the note above — this is deliberate.
  var FALLBACK = {
    id: MUN_ID,
    name: 'بلدية وادي الست',
    name_en: 'Wadi El Sitt Municipality',
    region: 'قضاء الشوف — محافظة جبل لبنان',
    website: 'https://municipality-wadi-el-sitt.org',
    phone: '+96176789039',
    whatsapp: '96176789039',
    emergency_phone: '+96176789039',
    email: 'management@municipality-wadi-el-sitt.org',
    address: null,
    primary_color: '#1a6eb5',
    secondary_color: '#1e5429'
  };

  var current = FALLBACK;
  var resolveReady;
  var ready = new Promise(function (r) { resolveReady = r; });

  function readCache() {
    try {
      var raw = localStorage.getItem(CACHE_KEY);
      if (!raw) return null;
      var c = JSON.parse(raw);
      return (c && c.row && c.row.id) ? c.row : null;
    } catch (e) { return null; }
  }

  function writeCache(row) {
    try { localStorage.setItem(CACHE_KEY, JSON.stringify({ at: Date.now(), row: row })); }
    catch (e) {}
  }

  // Merge rather than replace: a column left empty in the database must not
  // wipe out a working fallback. An empty phone field is not an instruction to
  // stop showing a phone number.
  function adopt(row) {
    if (!row) return;
    var merged = {};
    Object.keys(FALLBACK).forEach(function (k) { merged[k] = FALLBACK[k]; });
    Object.keys(row).forEach(function (k) {
      var v = row[k];
      if (v !== null && v !== undefined && v !== '') merged[k] = v;
    });
    current = merged;
  }

  adopt(readCache());

  function digits(s) { return String(s == null ? '' : s).replace(/[^0-9]/g, ''); }

  window.WadiMun = {
    ready: ready,
    get: function () { return current; },
    id: function () { return current.id || MUN_ID; },
    name: function () { return current.name || FALLBACK.name; },
    phone: function () { return current.phone || FALLBACK.phone; },
    email: function () { return current.email || FALLBACK.email; },
    website: function () { return current.website || FALLBACK.website; },
    region: function () { return current.region || ''; },
    address: function () { return current.address || ''; },
    // Falls back to the main number when no separate emergency line is set.
    emergency: function () { return current.emergency_phone || current.phone || FALLBACK.phone; },
    // wa.me wants digits with the country code and no plus sign.
    whatsapp: function () { return digits(current.whatsapp || current.phone || FALLBACK.whatsapp); },
    waLink: function (text) {
      var n = window.WadiMun.whatsapp();
      return 'https://wa.me/' + n + (text ? ('?text=' + encodeURIComponent(text)) : '');
    },
    telLink: function () { return 'tel:' + window.WadiMun.phone(); },
    emergencyTelLink: function () { return 'tel:' + window.WadiMun.emergency(); }
  };

  // ── refresh from the database ────────────────────────────────────────────
  // `municipalities` is readable by anon, so this works on the public pages
  // without a session. It carries no personal data — a name, a region, a
  // phone number and two colours.
  function load() {
    var sb = window.sb || window.supabaseClient || null;
    if (!sb || typeof sb.from !== 'function') return false;
    try {
      sb.from('municipalities').select('*').eq('id', MUN_ID).single()
        .then(function (r) {
          if (!r || r.error || !r.data) { resolveReady(current); return; }
          adopt(r.data);
          writeCache(r.data);
          resolveReady(current);
          try {
            document.dispatchEvent(new CustomEvent('wadi:municipality', { detail: current }));
          } catch (e) {}
        })
        .catch(function () { resolveReady(current); });
      return true;
    } catch (e) { resolveReady(current); return true; }
  }

  // The Supabase client is created by each page's own inline script, which may
  // run after this file. Try a few times, then give up quietly on the cache.
  var tries = 0;
  (function attempt() {
    if (load()) return;
    if (++tries > 40) { resolveReady(current); return; }   // ~8 seconds
    setTimeout(attempt, 200);
  })();
})();
