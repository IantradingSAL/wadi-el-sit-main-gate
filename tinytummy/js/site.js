/* Shared page behavior: nav toggle, product card rendering, image fallback. */

function ttNavToggle() {
  var links = document.querySelector('nav.links');
  if (links) links.classList.toggle('open');
}

/* Inline SVG placeholder shown until the real photo exists in images/. */
function ttPlaceholder(name) {
  var letter = (name || '?').trim().charAt(0).toUpperCase();
  var svg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400">' +
    '<rect width="400" height="400" fill="#f3ead2"/>' +
    '<circle cx="200" cy="170" r="90" fill="#f0b64b" opacity="0.25"/>' +
    '<text x="200" y="205" font-family="Verdana,sans-serif" font-size="110" font-weight="bold" ' +
    'fill="#17455e" text-anchor="middle">' + letter + '</text>' +
    '<text x="200" y="330" font-family="Verdana,sans-serif" font-size="26" ' +
    'fill="#64808e" text-anchor="middle">photo coming soon</text>' +
    '</svg>';
  return 'data:image/svg+xml,' + encodeURIComponent(svg);
}

function ttWaLink(productName) {
  var msg = 'Hello Tiny Tummy! I would like to order: ' + productName;
  return 'https://wa.me/' + TT_CONTACT.phone.replace(/\D/g, '') + '?text=' + encodeURIComponent(msg);
}

function ttPrice(p) {
  return (p.price === null || p.price === undefined || p.price === '')
    ? ''
    : '<span class="price">$' + Number(p.price).toFixed(2) + '</span>';
}

function ttProductCard(p) {
  var card = document.createElement('article');
  card.className = 'card';
  card.dataset.category = p.category;
  card.innerHTML =
    '<div class="photo"><img loading="lazy" alt="' + p.name + '"></div>' +
    '<div class="body">' +
    '  <div class="meta"><h3>' + p.name + '</h3><span class="tag">' + (p.age || '') + '</span></div>' +
    '  <p class="desc">' + (p.desc || '') + '</p>' +
    '  <div class="meta">' + ttPrice(p) +
    '    <div class="actions"><a class="btn btn-wa btn-sm" target="_blank" rel="noopener" href="' +
    ttWaLink(p.name) + '">Order on WhatsApp</a></div>' +
    '  </div>' +
    '</div>';
  var img = card.querySelector('img');
  img.onerror = function () { img.onerror = null; img.src = ttPlaceholder(p.name); };
  img.src = p.image;
  return card;
}

/* Render products into #product-grid; optional filter pills in .filters. */
async function ttRenderProducts(opts) {
  opts = opts || {};
  var grid = document.getElementById('product-grid');
  if (!grid) return;
  var products = await ttLoadProducts();
  if (opts.limit) products = products.slice(0, opts.limit);

  function draw(cat) {
    grid.innerHTML = '';
    products
      .filter(function (p) { return !cat || cat === 'all' || p.category === cat; })
      .forEach(function (p) { grid.appendChild(ttProductCard(p)); });
  }
  draw('all');

  var pills = document.querySelectorAll('.filters button');
  pills.forEach(function (b) {
    b.addEventListener('click', function () {
      pills.forEach(function (x) { x.classList.remove('active'); });
      b.classList.add('active');
      draw(b.dataset.cat);
    });
  });
}

/* Give every standalone photo box a graceful fallback too. */
document.addEventListener('DOMContentLoaded', function () {
  document.querySelectorAll('img[data-fallback]').forEach(function (img) {
    img.onerror = function () { img.onerror = null; img.src = ttPlaceholder(img.dataset.fallback); };
    if (img.complete && img.naturalWidth === 0) img.onerror();
  });
});
