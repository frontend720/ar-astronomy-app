/**
 * Overhead TLE Proxy — Cloudflare Worker
 *
 * Drop-in proxy in front of Celestrak's GP feed. Accepts the same query params
 * (?GROUP=stations&FORMAT=tle) so the iOS client only needs to swap the base URL.
 *
 * Uses Workers KV for caching (not the Cache API — caches.default is unreliable
 * on workers.dev subdomains and was causing every request to pass through to
 * Celestrak without being cached).
 *
 * KV binding required: TLE_CACHE (see wrangler.toml).
 */

const CELESTRAK = "https://celestrak.org/NORAD/elements/gp.php";
const CACHE_TTL = 6 * 60 * 60; // seconds — matches SatelliteTrackingService.catalogRefreshInterval
const ALLOWED_GROUPS = new Set(["stations", "starlink"]);

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const group = (
      url.searchParams.get("GROUP") ??
      url.searchParams.get("group") ??
      ""
    ).toLowerCase();

    if (!ALLOWED_GROUPS.has(group)) {
      return new Response(
        "Bad request: GROUP must be 'stations' or 'starlink'",
        { status: 400 }
      );
    }

    // KV works everywhere including workers.dev, unlike caches.default.
    const cached = await env.TLE_CACHE.get(group);
    if (cached) {
      return new Response(cached, {
        headers: {
          "Content-Type": "text/plain; charset=utf-8",
          "X-Cache": "HIT",
        },
      });
    }

    let upstream;
    try {
      upstream = await fetch(`${CELESTRAK}?GROUP=${group}&FORMAT=tle`, {
        headers: {
          "User-Agent": "Overhead/1.0 (iOS TLE proxy; Cloudflare Worker)",
        },
      });
    } catch (err) {
      return new Response(`Failed to reach Celestrak: ${err.message}`, {
        status: 502,
      });
    }

    if (!upstream.ok) {
      return new Response(`Celestrak returned ${upstream.status}`, {
        status: 502,
      });
    }

    const text = await upstream.text();
    if (!text.trim()) {
      return new Response("Empty response from Celestrak", { status: 502 });
    }

    // expirationTtl tells KV to auto-evict after 6 hours.
    await env.TLE_CACHE.put(group, text, { expirationTtl: CACHE_TTL });

    return new Response(text, {
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "X-Cache": "MISS",
      },
    });
  },
};
