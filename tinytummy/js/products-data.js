/*
 * Static product catalog — the fallback used until Supabase is connected.
 *
 * Each product:
 *   handle    unique slug, also the image file name: images/<handle>.jpg
 *   name      display name
 *   category  'purees' | 'meals' | 'cakes'
 *   age       age suitability label
 *   price     number in USD, or null to hide the price until you set it
 *   desc      short description
 *
 * Run  tools/get-photos.mjs  on your own computer to download the real
 * photos from the live Shopify store into images/ with these exact names.
 * Edit prices here (or manage everything from dashboard.html once Supabase
 * is connected — see js/supabase-config.js).
 */
const TT_PRODUCTS = [
  {
    handle: 'puree-pack',
    name: 'Puree Pack',
    category: 'purees',
    age: '6M+',
    price: null,
    desc: 'A starter bundle of our four signature purees: Ratatouille, Milletflower, Heartbeet and Tropical Quinoa.'
  },
  {
    handle: 'ratatouille',
    name: 'Ratatouille',
    category: 'purees',
    age: '6M+',
    price: null,
    desc: 'A gentle garden-vegetable puree, cooked the slow way.'
  },
  {
    handle: 'milletflower',
    name: 'Milletflower',
    category: 'purees',
    age: '6M+',
    price: null,
    desc: 'Creamy millet blended with cauliflower for tiny first tastes.'
  },
  {
    handle: 'heartbeet',
    name: 'Heartbeet',
    category: 'purees',
    age: '6M+',
    price: null,
    desc: 'Sweet beetroot puree packed with color and iron.'
  },
  {
    handle: 'tropical-quinoa',
    name: 'Tropical Quinoa',
    category: 'purees',
    age: '6M+',
    price: null,
    desc: 'Quinoa with a sunny mix of tropical fruit.'
  },
  {
    handle: 'labneh',
    name: 'Labneh',
    category: 'meals',
    age: '7M+',
    price: null,
    desc: 'Homestyle labneh made from full-fat cow’s milk.'
  },
  {
    handle: 'tiny-balls-24m',
    name: 'Tiny Balls (24M+)',
    category: 'meals',
    age: '24M+',
    price: null,
    desc: 'Bite-size energy balls with biscuits, walnuts, cocoa, carob molasses and real vanilla.'
  },
  {
    handle: 'cake',
    name: 'Baby-Friendly Cake',
    category: 'cakes',
    age: '12M+',
    price: null,
    desc: 'Celebration cakes made with baby-friendly ingredients — ask us about flavors.'
  }
];

const TT_CATEGORIES = [
  { key: 'purees', label: 'Purees', note: 'All purees are suitable for 6M+' },
  { key: 'meals',  label: 'Finger Food', note: 'All meals are suitable for 7M+' },
  { key: 'cakes',  label: 'Cakes', note: 'Baby-friendly celebration cakes' }
];

const TT_CONTACT = {
  phone: '+96171008604',
  phoneDisplay: '+961 71 008 604',
  email: 'tinytummylb@outlook.com',
  instagram: 'https://www.instagram.com/tinytummylb/',
  facebook: 'https://www.facebook.com/tinytummylb/'
};
