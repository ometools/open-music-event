const canonicalHost = "openmusicevent.app";
const redirectHosts = new Set([
  "ome.social",
  "www.ome.social",
  "www.openmusicevent.app",
]);

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (redirectHosts.has(url.hostname.toLowerCase())) {
      url.protocol = "https:";
      url.hostname = canonicalHost;
      url.port = "";
      return Response.redirect(url.toString(), 301);
    }

    return env.ASSETS.fetch(request);
  },
};
