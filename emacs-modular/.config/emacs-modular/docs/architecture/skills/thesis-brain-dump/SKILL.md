---
name: thesis-brain-dump
description: Turn a brain dump of thesis ideas into annotated Org tasks plus the citekeys to look up. Use when the user pastes loose ideas for their thesis workflow and wants tasks and sources.
---

# Thesis brain dump

The user gives a loose brain dump. You return annotated Org tasks and the citekeys they need, and file them in the thesis task file.

## 1. Settings

Find them in this order and ask the user only for what is still missing:

1. `.dir-locals.el` in the project root: `sp-thesis-dump-tasks-file`, `sp-thesis-dump-heading`, `sp-thesis-dump-bib-files`, `sp-thesis-dump-keywords`, `sp-thesis-dump-tags`, `sp-thesis-dump-cite-style`, `sp-thesis-dump-citekey-style`, `sp-thesis-dump-context-file`.
2. Defaults: heading `Brain dumps`, keywords `TODO`, tags `thesis`, cite style `org-cite` (`[cite:@a;@b]`), citekey style "first author's surname in lowercase and the year".
3. Required, no default: the Org file that receives the tasks, and the BibTeX file(s) (or the answer that there are none).

Offer to write the answers to `.dir-locals.el` so the Emacs command `M-x sp-thesis-dump` and this skill share them.

## 2. Read the project

- Known citekeys: the `@type{key,` lines of the BibTeX files (`grep -ho '^@[A-Za-z]*{[^,]*' file.bib`). Skip `@string`, `@preamble`, `@comment`.
- Headlines already under the target heading, so you do not propose a task twice. When the `org-mcp` tools are connected, read the file through them; otherwise read it directly. Read only.
- The context file, if there is one.

## 3. Write the tasks

- One task per distinct piece of work; merge duplicates, split bundles, invent nothing the dump does not imply.
- Title: imperative, at most 80 characters. Summary: one to three sentences on what to do and why.
- Keyword from the allowed list (first is default), the project's tags, an `:EFFORT:` (`H:MM`) only when the dump gives a basis.
- Citekeys: the exact known key where the source is known; otherwise a new key in the citekey style. Never give a known key to another source.
- For every key that is not in the bibliography, a checklist line saying what to find (author, title, year as far as the dump says, `(?)` for guesses) and why. Never make up details.
- Questions you could not settle from the dump.

## 4. File them

Under a heading `Brain dump [<date>]` below the target heading, one level deeper than it:

```org
** Brain dump [2026-10-21 Wed 20:50]
*** TODO Compare Smith with Jones :thesis:
:PROPERTIES:
:EFFORT: 1:30
:CITEKEYS: smith2020 jones2018
:END:
Read both and tabulate the sampling choices.
Sources: [cite:@smith2020;@jones2018]
To look up: jones2018
*** Citekeys
- [ ] =jones2018= :: Jones, 2018, on sampling. Baseline. (for: Compare Smith with Jones)
- Already in the bibliography: smith2020
*** Questions
- [ ] Which chapter does this belong to?
```

Use the `org-mcp` edit tools when connected, otherwise edit the file. Keep the user's raw dump in a `Raw dump` sub-heading, inside `#+begin_example` with lines that start with `*` or `#+` escaped by a comma. End with a short summary: how many tasks, which keys to look up.
