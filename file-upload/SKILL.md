---
name: file-upload
description: Upload a local file to the public file host and get back a permanent URL. Use when the user asks to upload a file, or when a screenshot, recording, HTML page, or other file needs a public URL, such as for a PR description.
metadata:
  harness: [claude, codex]
  platform: [win32, linux, darwin]
  scope: fleet
  requires: "curl; FILE_HOST_URL and FILE_HOST_TOKEN in the environment (see worker/README.md)"
---

# File upload

Upload files to the host at `$FILE_HOST_URL` and return the permanent public URL from the response body. Authenticate with `FILE_HOST_TOKEN`. If either variable is unset, tell the user instead of guessing. The host is a Cloudflare Worker backed by R2; its source and deploy steps live in `file-upload/worker/` in this repo, and the user deploys their own copy under their own domain.

## Upload

```bash
curl -sS --fail-with-body -X PUT -T <path-to-file> \
  -H "X-Upload-Token: $FILE_HOST_TOKEN" \
  "$FILE_HOST_URL/<filename>"
```

- Look at the file before it goes up. The host is link-only and unindexed, but
  anyone with the link can read: never upload secrets, private URLs or local
  filesystem paths, and crop or redact a screenshot that shows them.
- Use only the file's basename for `<filename>`, such as `login-flow.mp4`. The server slugifies it and adds a random suffix, so names do not need to be unique.
- Treat the response body as the permanent public URL and use it directly.
- HTML documents can be updated in place: PUT to the filename from the previously returned URL (the part after the domain) and the server overwrites it, so the URL stays stable.
- Everything else is served as immutable and cached for a year, so a replaced image or video would look stale. Upload a revised media file under its original basename again and use the new URL it returns.
- On HTTP 401, report that the token is wrong or unset. Do not retry.
- The example is bash syntax. From PowerShell, call `curl.exe` and use `$env:FILE_HOST_URL` and `$env:FILE_HOST_TOKEN`.

## Delete

```bash
curl -sS --fail-with-body -X DELETE \
  -H "X-Upload-Token: $FILE_HOST_TOKEN" \
  "$FILE_HOST_URL/<key from the URL>"
```

204 when gone, 404 when there was nothing under that key. Delete only what
the user asks to remove or what a re-upload has replaced.

## List

```bash
curl -sS --fail-with-body -H "X-Upload-Token: $FILE_HOST_TOKEN" "$FILE_HOST_URL/_list"
```

Every stored file, newest first, one per line: upload time, size in bytes, URL.
Use it to find the key of an older file before a delete, or to show the user
what is on the host when they want to clean up.

## Use the URL in GitHub

- Embed images (`png`, `jpg`, `gif`, `webp`) as `![description](URL)`.
- Link videos (`mp4`, `mov`, `webm`) as `[📹 screen recording](URL)` because GitHub does not inline-play externally hosted video.
- When an inline preview genuinely helps and the clip is shorter than about 30 seconds, also upload a GIF preview:

```bash
ffmpeg -i recording.mp4 -vf "fps=10,scale=800:-1" -loop 0 preview.gif
```

Embed the GIF and link the full-quality video below it.
