---
name: wait-what
description: Restate the last reply in plain words. Use when the user says "wait what", "in simpler terms", or that a reply was too long or too technical.
metadata:
  harness: [claude, codex]
  platform: [win32, linux, darwin]
  scope: fleet
---

# Wait what

The last reply lost the user. Say it again as you would to a colleague who
walked in mid-conversation, in at most six short sentences:

1. **What happened**: the outcome, in everyday words.
2. **What it means for the user**: the consequence they care about, such as
   what works now, what is still broken, or what it costs.
3. **The next step**: one, with the question you need answered if there is
   one.

Name things by what the user sees, not by how the system is built. Keep a
technical term only when the user must act on it, and explain it in the same
sentence. No lists of options, no file paths unless the user needs to open
one, no new information. The user may be listening rather than reading, so
every sentence must stand alone when heard.

If the user asks for more, the detail comes next, one question at a time.
