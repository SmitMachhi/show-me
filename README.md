# show-me

Your agent writes one HTML page. show-me opens it in your browser. You click the part you mean and type your note. The agent gets your words plus the exact element.

## Install

No downloads exist yet. Build from source with Zig 0.17.1:

```sh
git clone https://github.com/SmitMachhi/show-me
cd show-me
zig build-exe src/main.zig -O ReleaseSafe -femit-bin=show-me
```

On Windows, end that last line with `show-me.exe`.

1. Put the program on your PATH.
2. Copy the `skill` folder to `~/.claude/skills/show-me`.
3. For diagrams, install Graphviz. The rest runs without it.

## Use

Ask your agent to show you the plan or the design with show-me. To run the loop by hand:

```sh
show-me open plan.html                        # checks the page, opens it, returns
show-me wait plan.html                        # blocks until you send notes, prints them
show-me wait plan.html --reply "Title fixed"  # shows the reply, waits again
```

| Command | Does |
| --- | --- |
| `show-me` | Lists your reviews and their unread notes |
| `show-me check <file>` | Draws the diagrams, checks your writing rules |
| `show-me reply <file> "text"` | Shows one reply in the chat |
| `show-me end <file>` | Ends the review |
| `show-me export <file>` | Writes one file that opens without show-me |
| `show-me stop` | Stops the background daemon |

## In the browser

- Click any element, or select text, and write your note right there.
- Paste or drop images into any note.
- The green count shows what changed since your last send. Click it to step through.
- The amber count lists layout problems the page found in itself. One click asks the agent to fix them.
- Your notes wait on disk if no agent listens. Kill the agent mid-wait and you lose nothing.

## Diagrams

The agent writes DOT. show-me draws it.

```html
<script type="text/vnd.graphviz">digraph { cli -> daemon -> browser }</script>
```

One diagram costs the agent 2 to 3 KB of DOT. The drawn SVG runs 14 to 28 KB, and the agent never touches it.

## Writing rules

Put rule names in `~/.show-me/rules`, one per line. `check` and `open` then refuse any page that breaks one.

```
no-indefinite-articles
no-em-dash
no-contractions
no-external-assets
max-sentence-words 25
```

No file means no rules.

## Built with

One Zig program is both the command and the background daemon. It uses the standard library and zero packages. It listens on 127.0.0.1 and nowhere else. The daemon holds about 1.6 MB of memory and stops itself after 30 idle minutes.

The `design` folder has the system design as Graphviz files.

## Status

I run it on Windows. The Linux and macOS builds compile, and nobody has run them yet.

Still missing: whiteboard, public share links, access from your phone.
