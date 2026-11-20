# Measurements

Date: 2026-11-20. One machine, Windows 11. Linux and macOS: not measured.

`timeit.rs` measures full wall time from process start to process exit. Each time is the median of 20 runs after 3 warm-up runs. The lavish-axi reply had 10 runs. Both daemons were in operation before the runs.

## Time for each command

| Command | show-me 0.1.1 | lavish-axi 0.1.96 |
| --- | ---: | ---: |
| `--version` | 10.9 ms | 304.9 ms |
| List reviews | 12.9 ms | 835.0 ms |
| Open, daemon in operation | 13.3 ms | 858.8 ms |
| Reply | 13.8 ms | 864.6 ms |
| Check, 5 diagrams from cache | 13.5 ms | no such command |

## Memory of the background process

| | show-me | lavish-axi |
| --- | ---: | ---: |
| Private | 1.5 MB | 70.9 MB |
| Working set | 5.0 MB | 73.9 MB |

## Text that the agent reads

| Output | show-me | lavish-axi |
| --- | ---: | ---: |
| Open | 41 bytes | 3,090 bytes |
| List, 1 review | 114 bytes | 10,656 bytes |
| Reply | 5 bytes | 352 bytes |

The lavish-axi list contains its help text. One list with no session has 10,493 bytes.

## Guidance text

| Event | show-me | lavish-axi |
| --- | ---: | ---: |
| Session start | 0 bytes | 10,493 bytes with the optional hook from `lavish-axi setup hooks`, 0 bytes without |
| Agent writes one page | 4,221 bytes (`SKILL.md`) | 1,820 bytes (`SKILL.md`), then 1,216 to 10,385 bytes for each playbook |
| All text | 6,579 bytes (`SKILL.md`, `base.html`) | 59,232 bytes (`SKILL.md`, help, `design`, 8 playbooks) |

## Conditions

- lavish-axi ran on Node 26.13.0 with `LAVISH_AXI_TELEMETRY=0`, with its own state folder and port. `node -e 0` alone takes 46 ms.
- show-me ran as the ReleaseSafe build, with its own state folder and port.
- Not measured: first start of each daemon, lavish-axi with telemetry on, time in the browser.

## Do the measurement again

```sh
rustc -C opt-level=2 bench/timeit.rs -o timeit
./timeit "show-me open" 20 show-me open plan.html --no-open
./timeit "lavish-axi open" 20 node <path>/lavish-axi/dist/cli.mjs plan.html --no-open
```

The folders `c`, `go`, `rust`, `zig` and `node` contain one small daemon in each language. `harness.rs` compared them before the choice of Zig.
