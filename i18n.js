/* ════════════════════════════════════════════════════════════════════════
   i18n.js — Multilingual core for بلدية وادي الست (Wadi El Sit Municipality)
   ════════════════════════════════════════════════════════════════════════
   USAGE in any page:

   1) Include this script in <head> BEFORE any other page script:
        <script src="i18n.js"></script>

   2) Define your page's translations by extending the T dictionary
      (typically right after this script loads, or in your inline <script>):

        I18N.extend({
          ar: { myTitle: 'العنوان', myBtn: 'حفظ' },
          en: { myTitle: 'Title',   myBtn: 'Save' },
          fr: { myTitle: 'Titre',   myBtn: 'Enregistrer' },
        });

   3) Mark translatable HTML elements:
        <h1 data-i18n="myTitle">العنوان</h1>
        <input data-i18n-placeholder="emailPh" placeholder="...">
        <button data-i18n-title="helpBtn" title="...">?</button>
        <p data-i18n-html="richIntro">رسالة مع <b>HTML</b></p>

   4) Mark a host for the language switcher (or leave .hdr — auto-detected):
        <div data-i18n-switcher></div>

   5) (Optional) Register a hook to refresh dynamic JS-rendered content
      whenever language changes:
        I18N.onApply(function(lang){ refreshMyDynamicWidget(); });

   The script auto-detects the user's preferred language from
   navigator.languages on first visit, then remembers their choice
   in localStorage under the key "wadi_lang".
   ════════════════════════════════════════════════════════════════════════ */

(function(global){
  'use strict';

  /* ─── Shared base dictionary ───
     Common keys that ALL pages share (header, footer, generic UI).
     Pages add their own keys via I18N.extend(). */
  var T = {
    ar: {
      /* Header */
      hdrName: 'بلدية وادي الست',
      hdrSub: 'قضاء الشوف',
      /* Generic */
      back: '← رجوع',
      home: '🏠 الرئيسية',
      loading: '⏳ جاري التحميل...',
      save: 'حفظ',
      cancel: 'إلغاء',
      submit: 'إرسال',
      close: 'إغلاق',
      yes: 'نعم',
      no: 'لا',
      error: 'خطأ',
      success: 'تم بنجاح',
      retry: 'إعادة المحاولة',
      search: 'بحث',
      /* Footer */
      footName: 'بلدية وادي الست',
      footSep: '· قضاء الشوف',
      footPower: '© 2026 — مدعوم من IanTrading SAL',
      helpBtn: 'مساعدة',
    },
    en: {
      hdrName: 'Wadi El Sit Municipality',
      hdrSub: 'Chouf District',
      back: '← Back',
      home: '🏠 Home',
      loading: '⏳ Loading...',
      save: 'Save',
      cancel: 'Cancel',
      submit: 'Submit',
      close: 'Close',
      yes: 'Yes',
      no: 'No',
      error: 'Error',
      success: 'Success',
      retry: 'Retry',
      search: 'Search',
      footName: 'Wadi El Sit Municipality',
      footSep: '· Chouf District',
      footPower: '© 2026 — Powered by IanTrading SAL',
      helpBtn: 'Help',
    },
    fr: {
      hdrName: 'Municipalité de Wadi El Sit',
      hdrSub: 'Caza du Chouf',
      back: '← Retour',
      home: '🏠 Accueil',
      loading: '⏳ Chargement...',
      save: 'Enregistrer',
      cancel: 'Annuler',
      submit: 'Envoyer',
      close: 'Fermer',
      yes: 'Oui',
      no: 'Non',
      error: 'Erreur',
      success: 'Succès',
      retry: 'Réessayer',
      search: 'Rechercher',
      footName: 'Municipalité de Wadi El Sit',
      footSep: '· Caza du Chouf',
      footPower: '© 2026 — Propulsé par IanTrading SAL',
      helpBtn: 'Aide',
    },
  };

  var afterApplyHooks = [];

  /* ─── Public API ─── */
  var I18N = {
    T: T,
    /* Extend T with page-specific keys.
       Pass an object: { ar: {...}, en: {...}, fr: {...} } */
    extend: function(extras){
      if(!extras) return;
      ['ar','en','fr'].forEach(function(lang){
        if(extras[lang]) Object.assign(T[lang], extras[lang]);
      });
    },
    /* Register a callback that runs after every setLang().
       Use this to refresh dynamic JS-rendered content. */
    onApply: function(fn){
      if(typeof fn === 'function') afterApplyHooks.push(fn);
    },
    /* Get the active dictionary */
    L: function(){ return T[document.documentElement.lang] || T.ar; },
    /* Pick a language variant from a multilingual field
       (string OR object {ar,en,fr}) */
    pickLang: function(field){
      var lang = document.documentElement.lang || 'ar';
      if(field && typeof field === 'object') return field[lang] || field.ar || field.en || '';
      return field || '';
    },
    setLang: setLang,
    moveIndicator: moveIndicator,
  };

  /* ─── Core: apply a language ─── */
  function setLang(lang){
    if(!T[lang]) lang = 'ar';
    try { localStorage.setItem('wadi_lang', lang); } catch(e){}
    var dict = T[lang];
    document.documentElement.lang = lang;
    document.documentElement.dir = (lang === 'ar') ? 'rtl' : 'ltr';
    if(dict.pageTitle) document.title = dict.pageTitle;

    document.querySelectorAll('[data-i18n]').forEach(function(el){
      var k = el.getAttribute('data-i18n');
      if(dict[k] !== undefined) el.textContent = dict[k];
    });
    document.querySelectorAll('[data-i18n-html]').forEach(function(el){
      var k = el.getAttribute('data-i18n-html');
      if(dict[k] !== undefined) el.innerHTML = dict[k];
    });
    document.querySelectorAll('[data-i18n-placeholder]').forEach(function(el){
      var k = el.getAttribute('data-i18n-placeholder');
      if(dict[k] !== undefined) el.placeholder = dict[k];
    });
    document.querySelectorAll('[data-i18n-title]').forEach(function(el){
      var k = el.getAttribute('data-i18n-title');
      if(dict[k] !== undefined) el.title = dict[k];
    });
    document.querySelectorAll('[data-i18n-aria]').forEach(function(el){
      var k = el.getAttribute('data-i18n-aria');
      if(dict[k] !== undefined) el.setAttribute('aria-label', dict[k]);
    });

    /* Switcher state */
    var switcher = document.querySelector('.lang-switch');
    if(switcher){
      switcher.querySelectorAll('.lang-opt').forEach(function(b){
        var isActive = b.dataset.lang === lang;
        b.classList.toggle('active', isActive);
        b.setAttribute('aria-selected', isActive ? 'true' : 'false');
      });
      moveIndicator();
    }

    /* Run page-registered hooks */
    afterApplyHooks.forEach(function(fn){
      try { fn(lang); } catch(e){ console.warn('i18n hook error:', e); }
    });
  }

  /* ─── Slide the active indicator pill in the switcher ─── */
  function moveIndicator(){
    var switcher = document.querySelector('.lang-switch');
    if(!switcher) return;
    var active = switcher.querySelector('.lang-opt.active');
    var indicator = switcher.querySelector('.lang-indicator');
    if(!active || !indicator) return;
    indicator.style.width = active.offsetWidth + 'px';
    indicator.style.transform = 'translateX(' + (active.offsetLeft - 3) + 'px)';
    switcher.classList.add('ready');
  }

  /* ─── Inject the switcher UI into the page ─── */
  function injectSwitcher(){
    if(document.querySelector('.lang-switch')) return;
    var host = document.querySelector('[data-i18n-switcher]') ||
               document.querySelector('.hdr') ||
               document.querySelector('header');
    if(!host) return;
    var el = document.createElement('div');
    el.className = 'lang-switch';
    el.setAttribute('role', 'tablist');
    el.setAttribute('aria-label', 'Language / اللغة');
    el.innerHTML =
      '<button class="lang-opt" data-lang="ar" onclick="I18N.setLang(\'ar\')" role="tab" aria-label="العربية" title="العربية">AR</button>' +
      '<button class="lang-opt" data-lang="en" onclick="I18N.setLang(\'en\')" role="tab" aria-label="English" title="English">EN</button>' +
      '<button class="lang-opt" data-lang="fr" onclick="I18N.setLang(\'fr\')" role="tab" aria-label="Français" title="Français">FR</button>' +
      '<span class="lang-indicator" aria-hidden="true"></span>';
    host.appendChild(el);
  }

  /* ─── Inject the switcher + safety CSS into the page ─── */
  function injectStyles(){
    if(document.getElementById('i18n-core-styles')) return;
    var s = document.createElement('style');
    s.id = 'i18n-core-styles';
    s.textContent = [
      /* Premium segmented pill switcher */
      '.lang-switch{position:relative;display:inline-flex;background:rgba(255,255,255,.14);border:1px solid rgba(255,255,255,.22);border-radius:100px;padding:3px;-webkit-backdrop-filter:blur(14px) saturate(140%);backdrop-filter:blur(14px) saturate(140%);box-shadow:0 2px 14px rgba(0,0,0,.12),inset 0 1px 0 rgba(255,255,255,.18);direction:ltr}',
      '.lang-opt{position:relative;z-index:2;background:transparent;border:none;color:rgba(255,255,255,.78);font-size:11.5px;font-weight:800;letter-spacing:.6px;padding:7px 13px;border-radius:100px;cursor:pointer;transition:color .25s ease;font-family:"Inter","Tajawal",sans-serif;min-width:38px;line-height:1;outline:none}',
      '.lang-opt:hover:not(.active){color:#fff}',
      '.lang-opt.active{color:#0f4d82}',
      '.lang-opt:focus-visible{box-shadow:0 0 0 2px rgba(255,255,255,.5)}',
      '.lang-indicator{position:absolute;top:3px;height:calc(100% - 6px);background:#fff;border-radius:100px;box-shadow:0 1px 3px rgba(0,0,0,.12),0 4px 10px rgba(15,77,130,.15);transition:transform .32s cubic-bezier(.4,0,.2,1),width .32s cubic-bezier(.4,0,.2,1);z-index:1;pointer-events:none;opacity:0;left:0;width:0}',
      '.lang-switch.ready .lang-indicator{opacity:1}',
      /* Switch fonts when EN/FR is active */
      'html[lang="en"] body,html[lang="fr"] body{font-family:"Inter","Tajawal",sans-serif}',
      'html[lang="en"] .hdr-name,html[lang="fr"] .hdr-name{letter-spacing:.2px}',
      /* Directional safety net — prevents RTL/LTR punctuation bleed */
      'html[lang="ar"]{direction:rtl}',
      'html[lang="en"],html[lang="fr"]{direction:ltr}',
      'html[lang="en"] body,html[lang="fr"] body{direction:ltr}',
      'html[lang="en"] input,html[lang="en"] textarea,html[lang="en"] select,html[lang="fr"] input,html[lang="fr"] textarea,html[lang="fr"] select{direction:ltr;text-align:left}',
      'html[lang="ar"] input,html[lang="ar"] textarea,html[lang="ar"] select{direction:rtl;text-align:right}',
      /* Phone-number inputs always LTR — digits read left-to-right universally */
      'html[lang="ar"] input[type="tel"],html[lang="ar"] input[inputmode="tel"]{direction:ltr;text-align:right}',
      '@media(max-width:480px){.lang-opt{font-size:10.5px;padding:6px 10px;min-width:32px}}',
    ].join('\n');
    document.head.appendChild(s);

    /* Inter font for EN/FR */
    if(!document.querySelector('link[href*="Inter:wght"]')){
      var link = document.createElement('link');
      link.rel = 'stylesheet';
      link.href = 'https://fonts.googleapis.com/css2?family=Inter:wght@500;600;700;800;900&display=swap';
      document.head.appendChild(link);
    }
  }

  /* ─── Detect preferred language ─── */
  function detectLang(){
    var saved = null;
    try { saved = localStorage.getItem('wadi_lang'); } catch(e){}
    if(saved && T[saved]) return saved;
    /* First visit — read browser/phone language preference list */
    var navList = (navigator.languages && navigator.languages.length)
      ? navigator.languages
      : [navigator.language || navigator.userLanguage || 'ar'];
    for(var i = 0; i < navList.length; i++){
      var code = String(navList[i] || '').toLowerCase().split('-')[0];
      if(T[code]) return code;
    }
    return 'ar';
  }

  /* ─── Bootstrap ─── */
  var initialLang = detectLang();
  /* Apply <html lang/dir> immediately to prevent layout flash */
  document.documentElement.lang = initialLang;
  document.documentElement.dir = (initialLang === 'ar') ? 'rtl' : 'ltr';

  function bootstrap(){
    injectStyles();
    injectSwitcher();
    setLang(initialLang);
  }
  if(document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', bootstrap);
  } else {
    bootstrap();
  }

  /* Keep indicator aligned on resize / late font load */
  window.addEventListener('resize', function(){ moveIndicator(); });
  window.addEventListener('load', function(){ setTimeout(moveIndicator, 80); });

  /* Expose globally */
  global.I18N = I18N;
  /* Convenience globals for inline onclick handlers */
  global.setLang = setLang;
  global.L = I18N.L;
  global.pickLang = I18N.pickLang;
})(typeof window !== 'undefined' ? window : this);
