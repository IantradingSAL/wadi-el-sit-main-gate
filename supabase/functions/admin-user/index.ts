// admin-user — Supabase Auth admin bridge.
//
// Authorisation used to be a row in `employees` with role 'manager'. That is a
// different system from the one the pages and the database use, and the two had
// drifted: the account with role `admin` holds users_create / users_edit /
// users_delete, is shown user management on the dashboard, and was refused here
// with "Managers only". One account — the owner's — had a manager row, so only
// the owner could ever create or delete a user.
//
// It now asks the same question the rest of the platform asks:
//   user_has_perm(caller, 'users_view' | 'users_create' | 'users_edit' | 'users_delete')
// which resolves per-user override → role default → super_admin → false. Grant
// someone users_create from the user screen and it works here too, with nothing
// else to change.
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('SB_SERVICE_KEY') ?? ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? 'https://onjbwhkmmtqnymhjnplw.supabase.co'
const AUTH_BASE = `${SUPABASE_URL}/auth/v1/admin/users`
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST,OPTIONS'
}
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })

// which permission each action needs
const PERM_FOR: Record<string, string> = {
  list:   'users_view',
  create: 'users_create',
  update: 'users_edit',
  delete: 'users_delete'
}

console.log('[admin-user] boot. SERVICE_KEY_set=', !!SERVICE_KEY, ' SUPABASE_URL=', SUPABASE_URL)

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })
  const trace: Record<string, unknown> = {}
  try {
    if (!SERVICE_KEY) {
      trace.step = 'missing_service_key'
      console.error('[admin-user]', trace)
      return json({ error: 'Server misconfig: SUPABASE_SERVICE_ROLE_KEY not available inside the edge function', trace }, 500)
    }

    const authHeader = req.headers.get('Authorization') || ''
    trace.has_auth_header = !!authHeader
    const jwt = authHeader.replace(/^Bearer\s+/i, '').trim()
    if (!jwt) {
      console.log('[admin-user] no_jwt', trace)
      return json({ error: 'Missing Authorization header', trace }, 401)
    }

    const meRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${jwt}` }
    })
    trace.me_status = meRes.status
    if (!meRes.ok) {
      trace.me_body = (await meRes.text()).slice(0, 500)
      console.log('[admin-user] me_failed', trace)
      return json({ error: 'Invalid or expired session', trace }, 401)
    }
    const me = await meRes.json()
    const callerId = me?.id
    trace.caller_id = callerId
    if (!callerId) {
      console.log('[admin-user] no_caller_id', trace)
      return json({ error: 'Session has no user id', trace }, 401)
    }

    const body = await req.json().catch(() => ({}))
    const { action, uid, email, password, name, role, updates } = body
    trace.action = action

    const needed = PERM_FOR[action as string]
    if (!needed) return json({ error: 'invalid action', trace }, 400)
    trace.permission_required = needed

    // the same question the pages and the row-level policies ask
    const permRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/user_has_perm`, {
      method: 'POST',
      headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_user: callerId, p_perm: needed })
    })
    trace.perm_status = permRes.status
    if (!permRes.ok) {
      trace.perm_body = (await permRes.text()).slice(0, 500)
      console.log('[admin-user] perm_lookup_failed', trace)
      return json({ error: 'Permission lookup failed', trace }, 500)
    }
    const allowed = await permRes.json().catch(() => false)
    trace.allowed = allowed
    if (allowed !== true) {
      console.log('[admin-user] refused', trace)
      return json({ error: `هذا الحساب لا يملك صلاحية ${needed}`, trace }, 403)
    }

    const H = { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, 'Content-Type': 'application/json' }
    let r: Response
    if (action === 'list') {
      r = await fetch(AUTH_BASE + '?per_page=200', { headers: H })
    } else if (action === 'create') {
      if (!email || !password) return json({ error: 'email and password required', trace }, 400)
      r = await fetch(AUTH_BASE, {
        method: 'POST', headers: H,
        body: JSON.stringify({ email, password, email_confirm: true, user_metadata: { name, role } })
      })
    } else if (action === 'update') {
      if (!uid) return json({ error: 'uid required', trace }, 400)
      r = await fetch(`${AUTH_BASE}/${uid}`, { method: 'PUT', headers: H, body: JSON.stringify(updates || {}) })
    } else {
      if (!uid) return json({ error: 'uid required', trace }, 400)
      r = await fetch(`${AUTH_BASE}/${uid}`, { method: 'DELETE', headers: H })
    }
    trace.admin_status = r.status
    const d = r.status === 204 ? { success: true } : await r.json().catch(() => ({}))
    if (r.status >= 400) {
      console.log('[admin-user] admin_failed', trace, d)
      return json({ error: (d as { msg?: string; message?: string }).msg || (d as { message?: string }).message || 'Admin call failed', admin: d, trace }, r.status)
    }
    return json(d, r.status)
  } catch (e) {
    console.error('[admin-user] threw', trace, e)
    return json({ error: (e as Error).message || 'Internal error', trace }, 500)
  }
})
