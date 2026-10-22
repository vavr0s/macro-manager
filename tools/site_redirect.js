// The first address of the website (Worker macro-manager.vavr0smacromanager.workers.dev) - sends visitors
// to https://macromanager.pages.dev, same path. Deploy from an empty folder (never from server/):
//   npx wrangler deploy site_redirect.js --name macro-manager --compatibility-date 2026-10-01
export default {
  fetch(req) {
    const u = new URL(req.url);
    return Response.redirect('https://macromanager.pages.dev' + u.pathname + u.search, 301);
  }
};
