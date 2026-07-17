# OME Under Construction

Static assets for the `ome-under-construction` Cloudflare Workers & Pages app.

Manually deploy the contents of `public/` through Cloudflare's **New deployment**
flow for `ome-under-construction`.

The uploaded bundle should include:

- `public/index.html`
- `public/_worker.js`
- `public/favicon.png`
- `public/apple-touch-icon.png`
- `public/assets/ome-mark-sphere-cage-2026-07-13.png`
- `public/assets/ome-schedule.jpeg`
- `public/assets/ome-artist-detail.jpeg`
- `public/assets/ome-updates.jpeg`
- `public/assets/ome-location.jpeg`
- `public/assets/ome-more.jpeg`
- `public/.well-known/oauth-client-metadata.json`
- `public/.well-known/apple-app-site-association`

The Pages worker keeps `https://openmusicevent.app` canonical and redirects
`ome.social`, `www.ome.social`, and `www.openmusicevent.app` to it while
preserving the request path and query string. Add those hostnames as custom
domains on the Pages project before deploying this bundle.
