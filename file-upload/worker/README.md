# File host worker

A Cloudflare Worker in front of an R2 bucket. `PUT /<filename>` with the
shared token stores a file under a slugified name with a random suffix and
returns its public URL. `GET /<key>` serves it to anyone with the link, with
`X-Robots-Tag: noindex`. `DELETE /<key>` and `GET /_list` need the token. HTML
documents are overwritten in place on a second PUT to the same key and served
with `no-cache`; everything else is served immutable for a year.

## Deploy

Needs a Cloudflare account with R2 enabled, a domain on Cloudflare, and
[wrangler](https://developers.cloudflare.com/workers/wrangler/) logged in
(`wrangler login`).

1. Create the bucket named in `wrangler.jsonc` (`file-host`):

   ```sh
   wrangler r2 bucket create file-host
   ```

2. In `wrangler.jsonc`, replace `files.example.com` with your own hostname.
   `workers_dev` is off, so the worker is unreachable until a real route
   exists. `custom_domain: true` makes Cloudflare create the DNS record.

3. Set the write token. Any long random string works:

   ```sh
   wrangler secret put UPLOAD_TOKEN
   ```

   The worker's `UPLOAD_TOKEN` and the client's `FILE_HOST_TOKEN` are the same
   value under two names.

4. Deploy from this directory:

   ```sh
   wrangler deploy
   ```

Then set, on every machine that uploads:

```sh
export FILE_HOST_URL=https://files.example.com
export FILE_HOST_TOKEN=<the token>
```

On Windows, `setx FILE_HOST_URL https://files.example.com` and
`setx FILE_HOST_TOKEN <the token>` from any PowerShell, then open a new one.

The `file-upload` skill reads both. Reads need no token, so keep links to
anything sensitive to yourself; the host is unindexed, not private.
