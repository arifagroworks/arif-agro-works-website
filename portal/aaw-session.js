/* Share only an explicitly selected portal session. This is not an authorization
 * mechanism: every module must verify the server-returned staff profile and RLS. */
(function () {
  'use strict';
  const requested = new URLSearchParams(location.search).get('role')?.toLowerCase();
  const context = requested === 'admin' ? 'master' : requested;
  const known = ['master', 'incharge', 'direct'];
  const selected = known.includes(context) ? context : null;
  window.AAWSession = Object.freeze({
    expectedRole: selected === 'master' || selected === 'incharge' ? selected : null,
    options(defaultRole) {
      const role = selected || (known.includes(defaultRole) ? defaultRole : null);
      return {auth: {
        ...(role ? {storageKey: 'aaw-portal-auth-' + role} : {}),
        persistSession: true, autoRefreshToken: true, detectSessionInUrl: false
      }};
    }
  });
}());
