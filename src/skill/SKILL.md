---
name: show-me
description: Show plans, system designs, code structure, comparisons and other visual answers as one HTML page with diagrams that the person reviews in the browser. The person clicks parts of the page and sends notes back. Use when the work is system design, architecture, data flow, module structure, how code fits together, or any answer with four or more connected parts. Draw without asking first.
---

# show-me

## Goal

Some answers have shape: parts, connections, steps, choices. Text hides that shape. Explain with visuals, not with text only. Build the page from diagrams, visual modules and graphics, so the person sees the structure and can point at one part of it.

Needs the `show-me` program on PATH. Diagrams need Graphviz.

## Loop

1. Copy `base.html` (next to this file) to `.show-me/<name>.html` in the project. Write the page there.
2. `show-me open <file>` checks the page, shows it in the browser and returns at once. If it prints problems, fix each line and run it again.
3. `show-me wait <file>` blocks until the person sends notes. Run it in the foreground. It prints one JSON note per line.
4. Edit the file. The browser reloads it.
5. `show-me wait <file> --reply "what changed"` shows your reply and waits again. Go to step 4. For one reply with several lines, write the reply to one file and use `--reply-file <path>`.

If `wait` is stopped by one time limit, run the same command again. No note is lost.
If `wait` says another wait took over, stop: one other agent listens to this review.
The note `{"kind":"end"}` means the person ended the review. Stop, and answer in chat. Do not open that file again unless they ask; then use `show-me open <file> --reopen`.
The note `{"kind":"closed"}` means no browser tab shows the review. Ask the person in chat whether to open it again or end it. Do not wait again until they answer.
When you finish first, run `show-me end <file>`.
`show-me export <file>` writes one file that opens without show-me, for sharing.
`show-me` alone lists every review and its unread notes. Use it to resume one.

## Notes

Each line is one note: `{"kind","selector","text","node","cell","note","images","issues","data","question"}`.
`note` holds the person's words. `selector` is the CSS path of the element they clicked. `text` is its text, or the text they selected. `node` is the diagram node or edge name. `cell` gives the row and column names of one table cell. `images` lists image files the person attached: read each one. Kind `drawing`: the person drew on one diagram in red. `text` names the nodes under the strokes and each line drawn from one node to another node; read the image only if `text` and `note` do not tell you the change. `issues` lists layout problems to fix, each with its selector. `data` comes from the page (see Forms). `question` names the form question of one answer, or `layout` for layout fixes.

## When to draw

| Work | Draw |
|---|---|
| Design of one system | Parts diagram, then one diagram per complex part |
| Flow or request path | Step chain, colored by who acts |
| Reading or planning code | Module graph: files or functions and who calls whom |
| Two designs compared | Two parts diagrams, side by side |
| Change to one design | Same diagram, changed nodes marked |

Fewer than four connected parts: answer in chat, no page.

## Diagrams

Write DOT, never SVG. The program draws it:

```html
<script type="text/vnd.graphviz">digraph { rankdir=LR; cli -> daemon -> browser }</script>
```

- Use that exact opening tag.
- Do not set `fontname`. Do not write `</script>` inside the DOT.
- More than 15 nodes or 20 edges: split into several diagrams.
- Name nodes with words the person knows. Their notes quote the node name.

## Page

- Every element must help the reader. No eyebrow labels, badges, icon tiles, gradient text or filler paragraphs.
- Lead with the decision or the answer. Put detail below it.
- Plain HTML and the CSS in `base.html`. No framework, no file from another site.
- Show first, then tell. Before each paragraph, ask if one visual module can carry it. Diagram for relations, table for records, side-by-side columns for options. Step chain for sequence, labeled figure for one thing with parts.
- Prose only for reasons and open questions. Keep it under each visual, short.
- Verify each claim against the code before it goes on the page.

## Forms

On form pages, put `data-showme-annotate="off"` on `<html>` so clicks use the controls.
To collect one choice, use native controls and send the final answer once:

```html
<button onclick="window.showme.send('Use plan B', {plan: 'B'})">Choose plan B</button>
```

The third argument takes options. `{question: "plan"}`: one later answer to the same question replaces this answer while both are unsent. `{now: true}` sends at once. `{end: true}` sends, then ends the review.
