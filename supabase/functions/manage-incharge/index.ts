import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
"Access-Control-Allow-Origin": "*",
"Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
"Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(data: unknown, status = 200): Response {
return new Response(JSON.stringify(data), {
status,
headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
});
}

function clean(value: unknown): string {
return typeof value === "string" ? value.trim() : "";
}

function validUUID(value: string): boolean {
return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

function usernameToEmail(username: string): string {
return `${username.toLowerCase()}@incharge.arifagroworks.local`;
}

function fail(stage: string, message: string, status = 500): Response {
console.error(`[manage-incharge] ${stage}: ${message}`);
return reply({ error: message, stage }, status);
}

serve(async (req: Request): Promise<Response> => {
if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
if (req.method !== "POST") return reply({ error: "Method not allowed" }, 405);

try {
const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
const publicKey = (Deno.env.get("SUPABASE_ANON_KEY") || Deno.env.get("SUPABASE_PUBLISHABLE_KEY"))?.trim();

if (!supabaseUrl) return fail("configuration", "SUPABASE_URL is unavailable");
if (!serviceKey) return fail("configuration", "SUPABASE_SERVICE_ROLE_KEY is unavailable");
if (!publicKey) return fail("configuration", "SUPABASE_ANON_KEY / SUPABASE_PUBLISHABLE_KEY is unavailable");

const authorization = req.headers.get("Authorization") || "";
const token = authorization.replace(/^Bearer\s+/i, "").trim();
if (!token) return reply({ error: "Login required" }, 401);

const admin = createClient(supabaseUrl, serviceKey, {
auth: { autoRefreshToken: false, persistSession: false },
});
const authClient = createClient(supabaseUrl, publicKey, {
auth: { autoRefreshToken: false, persistSession: false },
global: { headers: { Authorization: authorization } },
});

const { data: userResult, error: userError } = await authClient.auth.getUser(token);
const userId = userResult?.user?.id;
if (userError || !userId) {
console.warn("[manage-incharge] user authentication failed:", userError?.message || "No user");
return reply({ error: "Invalid login session", stage: "authentication" }, 401);
}

const { data: masterProfile, error: masterError } = await admin
.from("staff_profiles")
.select("user_id,role,full_name")
.eq("user_id", userId)
.maybeSingle();

if (masterError) return fail("master_profile_query", `Unable to verify admin: ${masterError.message}`);
if (masterProfile?.role !== "master") {
return reply({ error: "Master Admin only", stage: "authorization" }, 403);
}

const {data: activeMaster, error: activeError} = await authClient.rpc("is_master_admin");
if (activeError || activeMaster !== true) return reply({error: "Active Master Admin required"}, 403);

let body: Record<string, unknown>;
try {
const parsed: unknown = await req.json();
if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
return reply({ error: "JSON object required" }, 400);
}
body = parsed as Record<string, unknown>;
} catch {
return reply({ error: "Invalid JSON request" }, 400);
}

const action = clean(body.action).toLowerCase();

if (action === "list") {
const { data: profiles, error: listError } = await admin
.from("staff_profiles")
.select("user_id,full_name,role")
.eq("role", "incharge")
.order("full_name", { ascending: true });

if (listError) return fail("list_profiles", `Unable to load accounts: ${listError.message}`);

const users = [];
for (const profile of profiles || []) {
const { data: authResult, error: authError } = await admin.auth.admin.getUserById(profile.user_id);
if (authError) console.warn("[manage-incharge] account lookup failed:", authError.message);
users.push({
user_id: profile.user_id,
full_name: profile.full_name,
role: profile.role,
email: authError ? null : authResult.user?.email ?? null,
username: authResult.user?.email?.endsWith("@incharge.arifagroworks.local") ? authResult.user.email.split("@")[0] : null,
is_enabled: !authResult.user?.banned_until || new Date(authResult.user.banned_until).getTime() <= Date.now(),
});
}
return reply({ success: true, incharges: users, accounts: users, data: users });
}

if (action === "create") {
const fullName = clean(body.full_name ?? body.fullName ?? body.name);
const username = clean(body.username).toLowerCase();
const password = clean(body.password);

if (fullName.length < 2 || fullName.length > 100) {
return reply({ error: "Full name must be 2-100 characters" }, 400);
}
if (!/^[a-z0-9_.-]{4,30}$/.test(username)) {
return reply({ error: "Username must be 4-30 characters (letters, numbers, _, ., -)" }, 400);
}
if (password.length < 8) return reply({ error: "Password must be at least 8 characters" }, 400);

const {error: auditError} = await authClient.rpc("aaw_log_admin_action", {p_action:"create_incharge",p_target:null,p_details:{username,full_name:fullName,status:"requested"}});
if(auditError) return fail("audit", "Unable to record the administrative request");
const email = usernameToEmail(username);
const { data: created, error: createError } = await admin.auth.admin.createUser({
email,
password,
email_confirm: true,
user_metadata: { full_name: fullName, username },
});
if (createError || !created.user) {
return reply({ error: createError?.message || "Unable to create account", stage: "create_auth_user" }, 400);
}

const newUserId = created.user.id;
const { error: profileError } = await admin.from("staff_profiles").insert({
user_id: newUserId,
full_name: fullName,
role: "incharge",
});
if (profileError) {
const { error: rollbackError } = await admin.auth.admin.deleteUser(newUserId);
return fail(
"create_profile",
`Unable to create incharge profile: ${profileError.message}${rollbackError ? "; rollback failed" : ""}`,
);
}
return reply({
success: true,
message: "Incharge created successfully",
user_id: newUserId,
full_name: fullName,
username,
email,
});
}

if (action === "reset_password" || action === "change_password") {
const userIdToEdit = clean(body.user_id ?? body.userId);
const password = clean(body.password ?? body.new_password);
if (!validUUID(userIdToEdit)) return reply({ error: "Invalid incharge ID" }, 400);
if (password.length < 8) return reply({ error: "Password must be at least 8 characters" }, 400);

const { data: profile, error: profileError } = await admin
.from("staff_profiles")
.select("role")
.eq("user_id", userIdToEdit)
.maybeSingle();
if (profileError) return fail("password_profile_query", profileError.message);
if (profile?.role !== "incharge") return reply({ error: "Incharge account not found" }, 404);

const {error: auditError} = await authClient.rpc("aaw_log_admin_action", {p_action:"reset_password",p_target:userIdToEdit,p_details:{status:"requested"}});
if(auditError) return fail("audit", "Unable to record the administrative request");
const { error: updateError } = await admin.auth.admin.updateUserById(userIdToEdit, { password });
if (updateError) return reply({ error: updateError.message, stage: "password_update" }, 400);
return reply({ success: true, message: "Password updated successfully" });
}

return reply({ error: "Unknown action", supported_actions: ["list", "create", "reset_password", "change_password"] }, 400);
} catch (error) {
const message = error instanceof Error ? error.message : String(error);
return fail("unexpected_exception", `Internal server error: ${message}`);
}
});
