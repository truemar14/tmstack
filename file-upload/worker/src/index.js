const MIME = {
  png: "image/png",
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  gif: "image/gif",
  webp: "image/webp",
  svg: "image/svg+xml",
  mp4: "video/mp4",
  mov: "video/quicktime",
  webm: "video/webm",
  pdf: "application/pdf",
  txt: "text/plain; charset=utf-8",
  md: "text/plain; charset=utf-8",
  json: "application/json",
  html: "text/html; charset=utf-8",
  zip: "application/zip",
};

function contentTypeFor(key, headerValue) {
  if (headerValue && headerValue !== "application/octet-stream") return headerValue;
  const ext = key.split(".").pop().toLowerCase();
  return MIME[ext] || "application/octet-stream";
}

// "Login Flow (Final).mp4" -> "login-flow-final-k3f9x2ab.mp4"
function makeKey(filename) {
  const dot = filename.lastIndexOf(".");
  const ext = dot > 0 ? filename.slice(dot + 1).toLowerCase().replace(/[^a-z0-9]/g, "") : "";
  const base = (dot > 0 ? filename.slice(0, dot) : filename)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 60) || "file";
  const bytes = crypto.getRandomValues(new Uint8Array(5));
  const suffix = Array.from(bytes, (b) => "abcdefghijklmnopqrstuvwxyz0123456789"[b % 36]).join("");
  return `${base}-${suffix}${ext ? "." + ext : ""}`;
}

// Writes (PUT, DELETE) need the shared token; reads need only the link.
function authorized(request, env) {
  const token = request.headers.get("X-Upload-Token");
  return !!env.UPLOAD_TOKEN && token === env.UPLOAD_TOKEN;
}

// The host is link-only: nothing lists it, and a leaked link must not become a search result.
const NOINDEX = { "x-robots-tag": "noindex, nofollow" };

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const key = decodeURIComponent(url.pathname.slice(1));

    if (request.method === "PUT") {
      if (!authorized(request, env)) return new Response("unauthorized\n", { status: 401 });
      if (!key || key.includes("/")) {
        return new Response("expected PUT /<filename> with no slashes\n", { status: 400 });
      }
      // An HTML document PUT to its previously returned key is overwritten in
      // place, so its URL stays stable across iterations (it is served with
      // no-cache, see GET). Everything else is served immutable, so a re-upload
      // always gets a fresh random key instead of a stale-cached overwrite.
      const existing = await env.BUCKET.head(key);
      const inPlace = !!existing && (existing.httpMetadata?.contentType || "").includes("text/html");
      const stored = inPlace ? key : makeKey(key);
      await env.BUCKET.put(stored, request.body, {
        httpMetadata: {
          contentType: contentTypeFor(stored, request.headers.get("Content-Type")),
        },
      });
      return new Response(`${url.origin}/${stored}`, { status: inPlace ? 200 : 201 });
    }

    if (request.method === "DELETE") {
      if (!authorized(request, env)) return new Response("unauthorized\n", { status: 401 });
      if (!key || key.includes("/")) return new Response("expected DELETE /<key>\n", { status: 400 });
      if (!(await env.BUCKET.head(key))) return new Response("not found\n", { status: 404 });
      await env.BUCKET.delete(key);
      return new Response(null, { status: 204 });
    }

    // GET /_list with the token: every stored file, newest first, one per line as
    // "<uploaded ISO>\t<bytes>\t<url>". "_list" can never be a stored key (every
    // key carries a random suffix), so the path is free for this.
    if (request.method === "GET" && key === "_list") {
      if (!authorized(request, env)) return new Response("unauthorized\n", { status: 401 });
      const objects = [];
      let cursor;
      do {
        const page = await env.BUCKET.list({ limit: 1000, cursor });
        objects.push(...page.objects);
        cursor = page.truncated ? page.cursor : undefined;
      } while (cursor);
      objects.sort((a, b) => b.uploaded - a.uploaded);
      const lines = objects.map((o) => `${o.uploaded.toISOString()}\t${o.size}\t${url.origin}/${o.key}`);
      return new Response(lines.join("\n") + (lines.length ? "\n" : ""), {
        headers: { "content-type": "text/plain; charset=utf-8", ...NOINDEX },
      });
    }

    if (request.method === "GET" || request.method === "HEAD") {
      if (!key) return new Response("file host\n", { headers: NOINDEX });
      const object =
        request.method === "HEAD" ? await env.BUCKET.head(key) : await env.BUCKET.get(key);
      if (!object) return new Response("not found\n", { status: 404, headers: NOINDEX });
      const headers = new Headers(NOINDEX);
      object.writeHttpMetadata(headers);
      headers.set("etag", object.httpEtag);
      // HTML documents get updated in place (see PUT); everything else is
      // effectively immutable under its random key.
      const immutable = !(headers.get("content-type") || "").includes("text/html");
      headers.set("cache-control", immutable ? "public, max-age=31536000, immutable" : "no-cache");
      return new Response(request.method === "HEAD" ? null : object.body, { headers });
    }

    return new Response("method not allowed\n", { status: 405, headers: { allow: "GET, HEAD, PUT, DELETE" } });
  },
};
