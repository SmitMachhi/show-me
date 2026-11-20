# show-me

The agent writes one HTML page. show-me opens the page in the browser. The reviewer clicks one part of the page and writes one note. The agent receives the note and the exact element.

## Install

1. Download the file for the operating system from [Releases](https://github.com/SmitMachhi/show-me/releases).
2. Rename the file to `show-me` (`show-me.exe` on Windows).
3. Put the file in one folder on the PATH. On Linux and macOS, run `chmod +x show-me`.
4. Run `show-me setup`. This command writes the agent skill to `~/.claude/skills/show-me`.
5. Install Graphviz if the pages have diagrams. All other functions operate without Graphviz.

To build from source, install Zig 0.17.1 and run this command:

```sh
zig build-exe src/main.zig -O ReleaseSafe -femit-bin=show-me
```

## Use

Tell the agent to show the plan or the design with show-me. The agent then runs this loop:

```sh
show-me open plan.html                        # checks the page, opens the page, returns
show-me wait plan.html                        # waits for notes, then prints the notes
show-me wait plan.html --reply "Title fixed"  # shows the reply, then waits again
```

| Command | Function |
| --- | --- |
| `show-me` | Shows each review and the number of unread notes |
| `show-me check <file>` | Draws the diagrams and applies the writing rules |
| `show-me reply <file> "text"` | Shows one reply in the chat |
| `show-me end <file>` | Ends the review |
| `show-me export <file>` | Writes one file that opens without show-me |
| `show-me setup [folder]` | Writes the agent skill |
| `show-me stop` | Stops the background daemon |

## Browser functions

- One click on any element opens the note box at that element. Selected text opens the same box.
- The note box and the chat accept pasted images.
- The green number shows the changes since the last sent note. One click goes to the next change.
- The amber number shows layout problems that the page found. One click sends all problems to the agent.
- The disk keeps each note until the agent reads the note. If the agent command stops, the notes stay safe.

## Diagrams

The agent writes DOT. show-me draws the diagram.

```html
<script type="text/vnd.graphviz">digraph { cli -> daemon -> browser }</script>
```

One diagram uses 2 KB to 3 KB of DOT. The drawn SVG has 14 KB to 28 KB, and the agent does not read the SVG.

## Writing rules

The file `~/.show-me/rules` contains rule names, one on each line. The commands `check` and `open` refuse each page that breaks one rule.

```
no-indefinite-articles
no-em-dash
no-contractions
no-external-assets
max-sentence-words 25
```

If the file does not exist, no rule applies.

## Design

One Zig program is the command and the background daemon. The program uses the Zig standard library and no packages. The daemon listens on 127.0.0.1 and on no other address. The daemon uses approximately 1.6 MB of memory. The daemon stops after 30 minutes without use.

The `design` folder contains the system design as Graphviz files.

## Status

Each change runs through build and test on Windows, Linux and macOS.

Not available: whiteboard, public share links, phone access.

## License

MIT. See `LICENSE`.
