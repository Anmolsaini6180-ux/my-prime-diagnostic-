// ============================================================
// Edge Function: admin-create-staff
// ============================================================
// The ONLY way a new sub_admin/collection_agent account is ever
// created (Section 23). Runs server-side specifically because real
// account creation needs the Supabase Admin API (service-role key),
// which must never reach the browser — this function is the boundary.
//
// Flow:
//   1. Verify the CALLER (via their own JWT, anon-key client) is a
//      real, active main_admin. Per Section 23's literal wording
//      ("Main Admin can add: Sub Admin, Collection Agent"), only
//      main_admin may call this — not sub_admin.
//   2. Validate the requested role is 'sub_admin' or 'collection_agent'
//      ONLY. main_admin can never be requested here — the only way an
//      account becomes main_admin is the existing DB-level
//      owner_emails()/sync_owner_admins() bootstrap (see migration
//      0009), never an admin "create user" form. Rejected outright if
//      attempted.
//   3. Use supabase.auth.admin.inviteUserByEmail() (service-role
//      client, never exposed to the browser) — this creates a real
//      auth.users row and sends Supabase's own invite email, which
//      lets the new staff member set THEIR OWN password by following
//      the emailed link. No password is ever created, generated, or
//      seen by this function, matching the project's standing rule.
//   4. The existing DB trigger (handle_new_auth_user) fires
//      synchronously and creates the profiles row (role defaults to
//      'patient' since this is never an owner email). This function
//      then updates that row's role/parent_sub_admin_id via the
//      service-role client — the one legitimate, audited path for
//      this, intentionally bypassing RLS because this whole function
//      IS the reviewed replacement for a direct policy grant.
//   5. Logs the action to activity_log for a real audit trail.
// ============================================================
import { createClient } from 'jsr:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

  try {
    const authHeader = req.headers.get('Authorization') ?? '';
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    // Client scoped to the CALLER's own JWT — used only to find out
    // who is calling and what their real, current role is. Never used
    // for the privileged writes below.
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await callerClient.auth.getUser();
    if (userErr || !userData?.user) return json({ error: 'Not authenticated.' }, 401);

    const { data: callerProfile } = await callerClient
      .from('profiles')
      .select('role, status, full_name, email')
      .eq('id', userData.user.id)
      .maybeSingle();

    if (!callerProfile || callerProfile.role !== 'main_admin' || callerProfile.status !== 'active') {
      return json({ error: 'Only an active Main Admin can add staff.' }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const email = String(body.email || '').trim().toLowerCase();
    const fullName = String(body.full_name || '').trim();
    const phone = body.phone ? String(body.phone).trim() : null;
    const role = String(body.role || '').trim();
    const parentSubAdminId = body.parent_sub_admin_id || null;

    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: 'A valid email is required.' }, 400);
    if (!fullName) return json({ error: 'Full name is required.' }, 400);
    if (role !== 'sub_admin' && role !== 'collection_agent') {
      // Deliberately rejects 'main_admin' and anything else. This is
      // not a gap to "fix later" — Super Admin status is only ever
      // granted by the DB-level bootstrap, never this form.
      return json({ error: 'Role must be sub_admin or collection_agent.' }, 400);
    }

    // Privileged client — service-role key, exists ONLY inside this
    // server-side function, never sent to or readable by the browser.
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    if (role === 'collection_agent' && parentSubAdminId) {
      const { data: parent } = await adminClient.from('profiles').select('role').eq('id', parentSubAdminId).maybeSingle();
      if (!parent || parent.role !== 'sub_admin') {
        return json({ error: 'Selected reporting Sub Admin is not valid.' }, 400);
      }
    }

    const { data: invited, error: inviteErr } = await adminClient.auth.admin.inviteUserByEmail(email, {
      data: { full_name: fullName, phone },
    });
    if (inviteErr) return json({ error: inviteErr.message }, 400);

    const newUserId = invited.user.id;

    // The signup trigger already created a 'patient'-role profile row
    // synchronously — promote it to the requested staff role now.
    const { error: updateErr } = await adminClient
      .from('profiles')
      .update({ role, parent_sub_admin_id: role === 'collection_agent' ? parentSubAdminId : null, phone })
      .eq('id', newUserId);
    if (updateErr) return json({ error: 'Invite sent, but role assignment failed: ' + updateErr.message }, 500);

    await adminClient.from('activity_log').insert({
      actor_id: userData.user.id,
      actor_name: callerProfile.full_name || callerProfile.email,
      actor_role: 'main_admin',
      action: 'staff_invited',
      entity_type: 'profiles',
      entity_id: newUserId,
      metadata: { email, role, full_name: fullName },
    });

    return json({ success: true, user_id: newUserId, email, role });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : 'Unexpected error.' }, 500);
  }
});
