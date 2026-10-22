// One address for the website: combocrown.pages.dev and www.combocrown.com send visitors to https://combocrown.com
// (same path). Preview deployments (<hash>.combocrown.pages.dev) are left alone.
const MOVE = new Set(['combocrown.pages.dev', 'www.combocrown.com']);

export async function onRequest(ctx) {
  const u = new URL(ctx.request.url);
  if (MOVE.has(u.hostname))
    return Response.redirect('https://combocrown.com' + u.pathname + u.search, 301);
  return ctx.next();
}
