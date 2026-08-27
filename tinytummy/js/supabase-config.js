/*
 * Supabase wiring — fill in the two values below to go live.
 *
 * 1. In your Supabase project: SQL editor → run supabase/schema.sql
 * 2. Project Settings → API → copy the Project URL and the anon public key.
 * 3. Paste them here. That's it — products.html and index.html will start
 *    reading the `products` table instead of js/products-data.js, and
 *    dashboard.html becomes your production admin panel.
 *
 * While the two values are empty the site quietly uses the static catalog,
 * so nothing breaks before you connect it.
 */
const TT_SUPABASE_URL = '';      // e.g. 'https://abcdefgh.supabase.co'
const TT_SUPABASE_ANON_KEY = ''; // the anon / publishable key (NEVER the service_role key)

function ttSupabase() {
  if (!TT_SUPABASE_URL || !TT_SUPABASE_ANON_KEY || !window.supabase) return null;
  if (!window.__ttClient) {
    window.__ttClient = window.supabase.createClient(TT_SUPABASE_URL, TT_SUPABASE_ANON_KEY);
  }
  return window.__ttClient;
}

/* Returns products from Supabase when configured, else the static list. */
async function ttLoadProducts() {
  const client = ttSupabase();
  if (client) {
    try {
      const { data, error } = await client
        .from('products')
        .select('handle,name,category,age,price,description,image_url,available')
        .eq('available', true)
        .order('sort', { ascending: true });
      if (!error && data && data.length) {
        return data.map(function (p) {
          return {
            handle: p.handle,
            name: p.name,
            category: p.category,
            age: p.age,
            price: p.price,
            desc: p.description || '',
            image: p.image_url || ('images/' + p.handle + '.jpg')
          };
        });
      }
    } catch (e) {
      console.warn('Supabase unavailable, using static catalog', e);
    }
  }
  return TT_PRODUCTS.map(function (p) {
    return Object.assign({ image: 'images/' + p.handle + '.jpg' }, p);
  });
}
