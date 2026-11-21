# show-me

## Goal

Some answers have shape: parts, connections, steps, choices. Text hides that shape. The reader must build the picture from sentences.

show-me makes the agent explain with visuals, not with text only. The agent builds the page from diagrams, visual modules and graphics. The reviewer sees the structure, then points at the part in question.

## How it works

The agent makes HTML page. show-me opens the page in the browser. The reviewer clicks one part of the page and writes one note. The agent receives the note and the exact element.

## Install

Linux and macOS:

```sh
curl -fsSL https://raw.githubusercontent.com/SmitMachhi/show-me/master/install.sh | sh
```

Windows, in PowerShell:

```powershell
irm https://raw.githubusercontent.com/SmitMachhi/show-me/master/install.ps1 | iex
```

With Node or Bun, on each system:

```sh
npx show-me-cli
```

```sh
bunx show-me-cli
```

Each command does these steps:

1. Downloads the program to `~/.local/bin`.
2. Writes the agent skill for each agent folder in the home folder: Claude Code, Codex, OpenCode, GitHub Copilot, Cursor, Gemini and the shared `~/.agents`. Each one gets `skills/show-me` in its folder. No settings file changes.
3. Installs Graphviz with the system package manager, if Graphviz is not installed.
4. Adds `~/.local/bin` to the PATH, if the PATH does not contain that folder.

The npm package contains the installer only. The program goes on the PATH as one native file, because one npm or Bun command shim adds 12 ms to 260 ms to each command on Windows.

Downloads are available for Windows x86-64, Linux x86-64 and macOS on Apple silicon. For other systems, build from source: install Zig 0.17.1 and run this command:

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
| `show-me reply <file> "text"` | Shows one reply in the chat. `--file <path>` reads the reply from one file |
| `show-me end <file>` | Ends the review |
| `show-me export <file>` | Writes one file that opens without show-me, then names each local file that it could not include |

`wait` has these rules:

- One review has one listener. The newest `wait` takes over, and each older `wait` stops with one message.
- One note that the browser sends two times arrives one time.
- When no browser tab shows the review for 20 seconds, `wait` prints `{"kind":"closed"}` and stops.
| `show-me setup [folder]` | Writes the agent skill for each agent folder that exists, or into one given folder |
| `show-me stop` | Stops the background daemon |
| `show-me update` | Installs the newest release in the folder of the program |

## Browser functions

- One click on any element opens the note box at that element. Selected text opens the same box and marks the selected words.
- One click on one link makes one note on the link. Ctrl+click (Cmd+click on macOS) opens the link in one new tab, outside the sandbox. The review page never leaves the frame. Pages can start downloads.
- The note box and the chat accept images from the attach button, from paste and from drop.
- One dashed outline marks each element that has one queued note. One click on that element opens the note for edits.
- Each sent note shows its state: sent, seen, working (the agent changed the page), done (the agent replied). The tooltip shows the time of each step.
- One notice shows when the review is open in more than one tab of the browser.
- The page reloads when its HTML file changes, and when one stylesheet, script or image that it loads from its folder changes. The words in one open note box and the values of form fields stay. Password fields stay empty.
- The pen button on each diagram lets the reviewer draw on the diagram. The note contains the drawing as one image and the names of the nodes below the strokes.
- The pen button in the chat opens one blank sheet for one sketch. The message contains the sketch as one image.
- The green number shows the changes since the last sent note. One click goes to the next change.
- The amber number shows layout problems that the page found: content wider than the page, text or controls that are cut off or off the page, text that one box covers, and text that is hard to read on its background. One click lists them. Tick the problems to fix and press "Fix selected", or dismiss one. One problem found again after one fix says "Still there".
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

One Zig program is the command and the background daemon. The program uses the Zig standard library and no packages. The daemon listens on 127.0.0.1 and on no other address. The daemon stops after 30 minutes without use.

Measured on Windows 11 on 2026-11-20, median of 20 runs, with the daemon in operation:

| | show-me 0.1.1 | lavish-axi 0.1.96 |
| --- | ---: | ---: |
| Open one page | 13.3 ms | 858.8 ms |
| Reply | 13.8 ms | 864.6 ms |
| Daemon memory, no tab open | 1.5 MB | 70.9 MB |
| Text that `open` prints for the agent | 41 bytes | 3,090 bytes |

Measured on Windows 11 on 2026-11-21 with show-me 0.1.4 and later changes: with one tab open on one page that loads 10 files, the daemon uses 2.1 MB of memory and 0.3 % of one CPU core while idle.

## Status

Each change runs through build and test on Windows, Linux and macOS.

Not available: shape editor for diagrams (the pen draws freehand strokes only), public share links, phone access.

## License

MIT. See `LICENSE`.
