/**
 * wadi-perms.js — who may do what, client side.
 * ---------------------------------------------------------------
 * Reads the same three tables the database reads, and resolves them by the
 * same rule as the has_perm() SQL function:
 *
 *     user_permissions (the per-user tick)  →  role_permissions (role default)
 *
 * Roles come from public.user_roles, never from user_metadata: a signed-in
 * user can rewrite their own metadata from the browser console, so a page that
 * trusts it can be talked into opening for anyone.
 *
 * Include AFTER the supabase-js CDN script and after the page's own client:
 *     <script src="wadi-perms.js"></script>
 *
 * Usage:
 *     await WadiPerms.load(sb);          // once, after sign-in
 *     if (!WadiPerms.can('sandouk_view')) { ...refuse... }
 *     WadiPerms.hasRole('admin','mayor') // any of them
 *     WadiPerms.isSuper()
 *
 * The page gate is a courtesy, not the boundary — row-level security in the
 * database is what actually stops a request.
 * ---------------------------------------------------------------
 */
(function () {
  var STATE = null;   // { userId, email, roles: [], perms: {}, superAdmin: bool }

  function empty() { return { userId: '', email: '', roles: [], perms: {}, superAdmin: false }; }

  function pickClient(sb) {
    if (sb) return sb;
    if (typeof window !== 'undefined' && window.sb) return window.sb;
    return null;
  }

  async function load(sb, force) {
    var c = pickClient(sb);
    if (!c) return (STATE = STATE || empty());
    if (STATE && !force) return STATE;

    var out = empty();
    try {
      var u = await c.auth.getUser();
      var user = u && u.data && u.data.user;
      if (!user) { STATE = out; return out; }
      out.userId = user.id;
      out.email = user.email || '';

      var rr = await c.from('user_roles').select('role').eq('user_id', user.id);
      out.roles = ((rr && rr.data) || []).map(function (r) { return r.role; });
      out.superAdmin = out.roles.indexOf('super_admin') >= 0;

      if (out.roles.length) {
        // a permission granted by any one of the user's roles counts as granted,
        // matching bool_or() in has_perm()
        var rp = await c.from('role_permissions').select('role,perms').in('role', out.roles);
        ((rp && rp.data) || []).forEach(function (row) {
          var p = row.perms || {};
          Object.keys(p).forEach(function (k) {
            out.perms[k] = (out.perms[k] === true) ? true : !!p[k];
          });
        });
      }

      // the per-user tick overrides the role default, in both directions
      var up = await c.from('user_permissions').select('perms').eq('user_id', user.id).maybeSingle();
      var ov = (up && up.data && up.data.perms) || {};
      Object.keys(ov).forEach(function (k) { out.perms[k] = !!ov[k]; });
    } catch (e) { /* stay closed on error — the caller refuses */ }

    STATE = out;
    return out;
  }

  function can(name) {
    if (!STATE) return false;
    if (STATE.perms && Object.prototype.hasOwnProperty.call(STATE.perms, name)) return !!STATE.perms[name];
    return !!STATE.superAdmin;      // a super admin passes checks nobody defined
  }

  function hasRole() {
    if (!STATE) return false;
    if (STATE.superAdmin) return true;
    var want = Array.prototype.slice.call(arguments);
    if (want.length && Array.isArray(want[0])) want = want[0];
    for (var i = 0; i < want.length; i++) if (STATE.roles.indexOf(want[i]) >= 0) return true;
    return false;
  }

  window.WadiPerms = {
    load: load,
    can: can,
    hasRole: hasRole,
    isSuper: function () { return !!(STATE && STATE.superAdmin); },
    roles: function () { return STATE ? STATE.roles.slice() : []; },
    all: function () { return STATE ? JSON.parse(JSON.stringify(STATE.perms)) : {}; },
    email: function () { return STATE ? STATE.email : ''; },
    loaded: function () { return !!STATE; },
    reset: function () { STATE = null; }
  };
})();
