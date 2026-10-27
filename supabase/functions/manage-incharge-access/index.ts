
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
"Access-Control-Allow-Origin": "https://arifagroworks.github.io",
"Access-Control-Allow-Headers":
"authorization, apikey, content-type, x-client-info",
"Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(data: unknown, status = 200) {
return new Response(JSON.stringify(data), {
status,
headers: {
...cors,
"Content-Type": "application/json",
},
});
}

serve(async (req) => {
if (req.method === "OPTIONS") {
return new Response(null, { status: 204, headers: cors });
}

if (req.method !== "POST") {
return reply({ error: "Method not allowed" }, 405);
}

try {
const url = Deno.env.get("SUPABASE_URL");
const anonKey =
Deno.env.get("SUPABASE_ANON_KEY") ||
Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!url || !anonKey || !serviceKey) {
return reply({ error: "Server configuration missing" }, 500);
}

const token = req.headers
.get("Authorization")
?.replace(/^Bearer\s+/i, "");

if (!token) {
return reply({ error: "Login required" }, 401);
}

const authClient = createClient(url, anonKey, {
global: { headers: { Authorization: "Bearer "+token } },
auth: {
persistSession: false,
autoRefreshToken: false,
},
});

const admin = createClient(url, serviceKey, {
auth: {
persistSession: false,
autoRefreshToken: false,
},
});

const { data: authData, error: authError } =
await authClient.auth.getUser(token);

if (authError || !authData.user) {
return reply({ error: "Invalid login session" }, 401);
}

const callerId = authData.user.id;

const { data: caller, error: callerError } = await admin
.from("staff_profiles")
.select("role")
.eq("user_id", callerId)
.single();

if (callerError || caller?.role !== "master") {
return reply({ error: "Master Admin only" }, 403);
}

const {data: activeMaster, error: activeError} = await authClient.rpc("is_master_admin");
if(activeError || activeMaster !== true) return reply({error:"Active Master Admin required"},403);
const body = await req.json();
const targetId = body.user_id;
const action = body.action;

if (
typeof targetId !== "string" ||
!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(targetId) ||
!["disable", "enable"].includes(action)
) {
return reply({ error: "Invalid request" }, 400);
}

if (targetId === callerId) {
return reply({ error: "Cannot modify own account" }, 403);
}

const { data: target, error: targetError } = await admin
.from("staff_profiles")
.select("user_id,full_name,role")
.eq("user_id", targetId)
.single();

if (targetError || target?.role !== "incharge") {
return reply({ error: "Incharge not found" }, 404);
}

const {error: auditError} = await authClient.rpc("aaw_log_admin_action", {p_action:action==="disable"?"disable_incharge":"enable_incharge",p_target:targetId,p_details:{status:"requested"}});
if(auditError) return reply({error:"Unable to record the administrative request"},500);
const banDuration =
action === "disable" ? "876000h" : "none";

const { error: updateError } =
await admin.auth.admin.updateUserById(targetId, {
ban_duration: banDuration,
});

if (updateError) {
return reply({ error: updateError.message }, 400);
}

return reply({
success: true,
user_id: targetId,
name: target.full_name,
action,
message:
action === "disable"
? "Incharge login disabled"
: "Incharge login enabled",
});
} catch (err) {
return reply({
error: err instanceof Error ? err.message : "Unexpected error",
}, 500);
}
});
