---
name: html-communication
description: Write a plan, spec, findings, report, comparison, or set of UI mock variants as one self-contained HTML page and publish it. Use when the user asks for any of those as HTML, asks for mocks or variants to pick from, or says "HTML" with no other context.
metadata:
  harness: [claude, codex]
  platform: [win32, linux, darwin]
  scope: fleet
  requires: "the Artifact tool (Claude Code); curl, FILE_HOST_URL and FILE_HOST_TOKEN in the environment (file-upload skill) for the file host case"
---

# HTML Communication

For documents meant to be read: plans, specs, findings, reports, comparisons,
UI mocks. Not for HTML that ships as part of a product.

## Where it goes

- **Artifact** (Claude Code): the default. Private to the user until they share
  it, comment threads on the page, renders in the viewer's theme, and a
  republish keeps the URL.
- **File host** (`$FILE_HOST_URL`, via the `file-upload` skill): when
  the link must open without a Claude login (a PR description, a mock set for
  the team), when the user says "public" or "upload", and always from Codex,
  which has no Artifact tool. The `file-upload` skill holds the host's rules:
  what may never go up, in-place updates, and the 401 case.

This skill makes HTML pages. When the user asks for a "doc", make a Claude doc
through the Claude Docs connector; when they ask for "slides" or a deck, make a
Slides artifact. A plan, report or review with no format named is an HTML page.

## Document

One self-contained HTML file, capped at 512 KB.

- Write it like a spec, not a landing page: dense, scannable, no hero,
  decorative chrome or marketing voice. Run the copy through the `unslop`
  skill's rules before publishing.
- Start the page's `<style>` with the contents of this skill's `style.css`
  (off-white ground, system type, one accent, dark theme through tokens) and
  style everything through its tokens: pages then look alike and follow the
  viewer's theme. This is the document's own style; it does not apply inside
  UI mocks (below).
- Use semantic HTML, inline CSS, inline SVG, and HTTPS or data-URL images. No
  linked stylesheets, external or module scripts, frames, embeds, or forms.
- Use an inline classic script only when interactivity materially helps, and
  keep the page readable without it.
- Give external links `target="_blank"` and `rel="noopener noreferrer"`.
- Write a complete document: doctype, `<meta charset>`, the viewport meta,
  `<title>`, `<style>`, then the content in `<main>`. The same file goes to
  either venue.

## UI Mocks

When the user asks for variants:

- Render real styled variants, not descriptions.
- Label them `A`, `B`, `C`... and lay them out for direct comparison.
- A mock of an existing product matches that product's colors, type, spacing,
  and components. A new surface with no design system to match follows the
  `frontend-design` skill. The document's own style stays outside the mocked
  interface.
- Keep one file across iterations so its URL stays stable.

## Publish

Publishing is part of this skill, not a separate step: every document it
creates or updates goes to one of the two venues before the reply ends, in
Auto mode too, without a further permission question. An Artifact starts
private, so the default venue exposes nothing; a user who wants to be asked
before the file host route says so in their instructions.

Artifact: write the file, call the Artifact tool on it (favicon on the first
publish; load `artifact-design` first), report the URL. To update, call it
again with the same file path, or with `url` for an Artifact from an earlier
session.

File host: write the file, upload it with the `file-upload` skill, report the
local path and the returned URL. To update, PUT to the filename from the
previously returned URL, as that skill describes. Upload under a fresh name
only when a separate new draft is wanted. Never claim the document is hosted
before the upload succeeds.

## Verify

Verification is separate from publishing and optional. Where browser tools are
available, open the URL, check it at desktop and phone widths, and fix what is
wrong before reporting. Skip it on a headless box; do not install a browser
for it.
