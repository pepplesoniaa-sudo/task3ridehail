# Content file spec for the Word build

You are writing ONE content file for a Word document build.
Write it with the Write tool to the EXACT path given in your task.
Output only the file. When done, reply with one line: `wrote <path> (<n> lines)`.
Do not run any build, do not read unrelated files, do not edit any source doc.

## Line markup (each directive on its own physical line)

- `# Heading`  chapter heading (Heading 1). Each file must contain EXACTLY ONE `# ` line, as its first line.
- `## Heading`  section heading (Heading 2).
- `### Heading`  subsection heading (Heading 3).
- `@SRC text`  italic small source line, one per chapter, naming the source files it was built from.
- `@P text`  one body paragraph, the WHOLE paragraph on ONE physical line (join wrapped lines). Plain English.
- `@B text`  a bullet item, one per line.
- `@CAP text`  a centred italic caption.
- `@IMG relative/path.png | caption`  an image. Path is relative to C:\dev\task3ridehail.
- `@CODE` then verbatim code lines then `@END`  a monospace block. Do not alter code, keep it exactly.
- `@TBL 9` then table rows then `@END`  a table. One row per line, cells separated by ` | `. The first row is the bold header. Use size 9, or 8 only for very wide tables.
- `@PAGE`  a page break.
- Blank lines are ignored.
- Do NOT use any other markup: no markdown tables, no `**`, no backticks, no `-` list markers.

## Content rules

1. Every sentence must come from the named source files. Do not invent any fact or number. Copy numbers exactly as written.
2. KEEP the labels CONFIRMED and INFERRED and the requirement IDs exactly as the source writes them: A1 to A5, B0 to B10, U1 to U4, Q1 to Q6, T0 to T9, P0 to P3, F1 to F19, PF1 to PF12, EP01 to EP27, JB1 to JB3, R1 to R20.
3. REMOVE every `[CLASS NOTE NEEDED: ...]` marker completely (delete the marker text). Keep the surrounding reasoning.
4. Plain English, one voice, same as the source. Prefer "to" for ranges (for example "16 to 42") instead of dashes. Avoid em dashes and en dashes.
5. Follow the section order and headings the task / outline asks for.
6. Do NOT add a title page or a contents list; the build adds those. Start at `# `.
7. Do NOT mention any other project, any course, or unrelated material.
8. Keep to the requested page budget. Be faithful but concise: prefer the source's own wording and numbers.

## Tables

Use `@TBL 9` and put the header row first. Keep cells short. Long name lists that the outline sends to an appendix must NOT be pasted here; just point to the appendix.

## Images

Only include images your task names, using the given file name and caption.
