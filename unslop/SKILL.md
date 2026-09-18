---
name: unslop
description: Cut AI tells from prose people will read. Use before a PR description, README, doc page, commit body, or post ships, or when the user says "unslop".
license: Complete terms in LICENSE.txt
metadata:
  harness: [claude, codex]
  platform: [win32, linux, darwin]
  scope: fleet
---

# Unslop

Edit text to remove AI patterns. Preserve meaning and match the intended
tone. This is for prose people read; a document written for an agent keeps
its leading words (see the `writing-for-agents` skill).

## Process

1. Scan for the patterns below.
2. Rewrite.
3. Self-audit: "What makes this obviously AI generated?" Fix remaining tells.

## Patterns to detect and fix

### Content

1. **Superficial -ing phrases.** "highlighting...", "ensuring...",
   "reflecting...", "showcasing...", "fostering...". Delete or expand with
   real sources.
2. **Vague attributions.** "Experts believe", "Industry reports suggest",
   "Some critics argue". Name the source or delete.

### Language

3. **Fancy words.** Additionally, crucial, delve, enduring, enhance, fostering,
   garner, interplay, intricate, landscape (abstract), pivotal, showcase,
   tapestry (abstract), testament, underscore, vibrant, utilize, leverage,
   facilitate, numerous. Replace with the plain word: use, help, many.
4. **Fancy ways to say "is".** "serves as", "stands as", "boasts",
   "features". Just say "is" or "has".
5. **"Not just X, but Y."** State the point directly instead.
6. **Rule of three.** Forcing ideas into groups of three. Use the natural
   number.
7. **Synonym cycling.** Protagonist, main character, central figure, hero all
   in one paragraph. Pick one, repeat it.
8. **False ranges.** "from X to Y" where X and Y are not on a meaningful
   scale. List topics directly.
9. **Filler and hedging.** "In order to" becomes "To". "Due to the fact that"
   becomes "Because". "It is important to note that" gets deleted. "Could
   potentially possibly be argued that it might" becomes "may".

### Style

10. **Em dashes.** Use periods or commas only: no em dashes, en dashes,
    parentheses as asides, or hyphens standing in for a dash. If a thought
    needs separation, end the sentence or use a comma.
11. **Colons as connectors.** Colons are fine before a list or example, not
    as mid-sentence glue. "If you're coming from traditional automation:
    instead of registering event handlers, you describe conditions" adds
    nothing with the colon. Let the point stand on its own: "Describing when
    the scheduler should fire works best as plain English."
12. **Boldface and inline-header lists.** Do not bold every proper noun or
    acronym. The list tell is a bold label and colon that restates the line:
    "**Performance:** Performance improved...". Convert those to prose. A bold
    lead-in that ends in a period, names the item, and is followed by
    genuinely new detail ("**Schema in TypeScript.** Tables live in one
    file.") is fine.
13. **Title case headings.** Use sentence case.

### Jargon

14. **Abstract metaphor nouns.** Substrate, wedge, vector, locus, vantage,
    nexus, primitive (as noun), harness (as metaphor), surface (as in "API
    surface"), bedrock, scaffolding (as metaphor), modality, paradigm,
    gold-plating, ratchet (as metaphor), evacuate (for moving code), endgame,
    north star, flywheel. These read as technical but usually have a plainer
    concrete word. "Substrate" becomes "base". "Wedge in" becomes "add".
    "Vector" becomes "way" or "method". "Gold-plating" becomes "more than the
    job needs". "Ratchet" becomes the mechanism's real name or "a limit that
    only tightens". "Evacuate" becomes "move out". "Endgame" becomes "the
    last phase". Pick the concrete word.

### Plain speech

15. **Say what it does, not how it feels.** "the database stays close at
    hand", "SQL you can read", "types that follow your schema" name a
    feeling. The fix names the mechanism or a number: "`.toSQL()` returns the
    exact string sent to the database", "a column rename fails the build".
    Ask what the sentence tells the reader to do or know, then write that. If
    you cannot restate it as a concrete instruction, fact, or number, cut it.
    One more check: if the sentence could appear unchanged in another
    project's docs, it says nothing about this one. Cut it.
16. **Shorten or split dense sentences.** If the reader has to backtrack to
    parse a sentence, break it in two or drop clauses. One idea per sentence.
17. **Active voice.** Catch "is/are/was/were + past participle" and name the
    actor: "queries are validated" becomes "the compiler validates queries",
    "the file is parsed by the loader" becomes "the loader parses the file".
    Passive is fine only when the actor is unknown or genuinely does not
    matter.
18. **Cut adverbs, or use a stronger verb.** "runs quickly" becomes "is fast"
    or the number. "significantly improves" becomes the measured delta. An
    adverb propping up a weak verb means the verb is wrong.
19. **Mannered prose.** Metaphor or flourish where a literal phrase exists:
    aphorisms ("wire it or delete it"), rhetorical fragments for effect,
    personified code ("the plan holds it"), figurative verbs ("rides along",
    "stands on"), stock framing phrases. "A dial worth turning" becomes "a
    parameter worth varying". Say what you mean. Rule 14 covers the metaphor
    nouns.
20. **Over-compression.** Dropped articles, verbless fragments, symbol-speak,
    and abbreviations that make the reader decode instead of read. "Parser
    rejects bad date → exit 2, no write" becomes "The parser rejects a bad
    date, exits with code 2, and writes nothing." Write whole sentences with
    their articles and verbs, and spell out arrows and abbreviations.
