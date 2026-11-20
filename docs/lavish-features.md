# lavish-axi v0.1.98: feature inventory

Source: read-only copy at `E:\show-me\e`. Goal: a checkable list for a feature-parity rebuild.

How to read this file:

- One row per feature. IDs are sequential across the whole file.
- Size class is rebuild effort: S is hours, M is a day or two, L is a week or more.
- Location names a file under `src/` unless it says README or docs. `inv` means `docs/invariants.md`. `acks` means `docs/delivery-acks.md`. `share-doc` means `docs/self-hosting-share.md`.
- Some behavior lives in the `axi-sdk-js` dependency (TOON output, `update`, hook installers). That code is not in this repo, so those rows say so.

## 1. CLI commands and flags

| ID | Feature | What it does for the person or agent | Where it lives | Size |
| --- | --- | --- | --- | --- |
| F-001 | `lavish-axi` (no args) home | Prints open sessions (file, status, url, pending_prompts, listener), the description, visual guidance, playbook list and help lines. | cli.js `createHomeOutput`, README CLI Reference | M |
| F-002 | `lavish-axi --help` | Prints static usage and poll rules without live sessions. | cli.js `createTopLevelHelp` | S |
| F-003 | `--version`, `-v`, `-V` | Prints the version before any state dir or telemetry work, so agent harness probes stay fast. | cli.js `isVersionOnlyArgv`, `run` | S |
| F-004 | `lavish-axi update [--check]` | Checks or installs the latest npm release. Provided by the AXI SDK, only reserved and passed through here. | cli.js `RESERVED_COMMANDS`, README | S |
| F-005 | `lavish-axi <html-file>` (bare form) | Rewrites a bare file argument to the `open` command and opens or resumes the session for that file. | cli.js `normalizeArgv`, `openCommand` | M |
| F-006 | `open --no-open` | Makes sure the server and session exist without launching a browser window. | cli.js `shouldOpenBrowser`, README Flags | S |
| F-007 | `open --no-gate` | Skips the open-time layout mask for this one browser open (one-open URL with `?no-gate=1`). | cli.js, inv Request flow 1 | S |
| F-008 | `open --reopen` | Reopens a session the user ended from the browser, which a plain open refuses. | cli.js, README Session end etiquette | S |
| F-009 | Open output shape | Returns `session {file,url,status}`, optional `network_warning`, optional `self_paint_warning`, and a `next_step` telling the agent to poll. | cli.js `createOpenOutput` | S |
| F-010 | User-ended open refusal | Returns status `user-ended` with guidance instead of reopening a session the human closed. | cli.js `createUserEndedOpenOutput`, server.js `/api/sessions` | S |
| F-011 | Open validation | Rejects a non-HTML path (`.html`/`.htm` only) and a missing file with typed errors and hints. | cli.js `assertHtmlFile`, artifact-path.js | S |
| F-012 | `lavish-axi poll <html-file>` | Long-polls with no timeout until the user sends feedback, ends the session, or all review tabs stay disconnected. | cli.js `pollCommand`, server.js `handlePoll` | L |
| F-013 | `poll --owner <label>` | Labels the process that listens, shown in the home session list. Empty, flag-like or `none` labels are refused. | cli.js `pollCommand`, README Flags | S |
| F-014 | `poll --takeover` | Displaces the current poll holder, which exits with `LISTENER_REPLACED`. | cli.js, server.js `activePolls`, inv Request flow 7 | M |
| F-015 | `poll --agent-reply "..."` | Posts a chat reply atomically, marks seen notes Done, then keeps waiting. | cli.js `resolveAgentReply`, server.js POST `/api/poll` | M |
| F-016 | `poll --agent-reply-file <path\|->` | Reads a Markdown reply from a file or stdin so newlines survive quoting. Cannot combine with `--agent-reply`. | cli.js `readAgentReplyFile` | S |
| F-017 | `poll --timeout-ms <ms>` | Test and debug escape hatch that ends the poll with status `waiting` after a delay. | cli.js `pollCommand` | S |
| F-018 | Poll status `feedback` | Returns `prompts`, optional `artifact_failures`, `next_step`, then `dom_snapshot` in that fixed order. Adds `session_ended` and `ended_by` for a final batch. | cli.js `createPollOutput`, inv Request flow 7 | M |
| F-019 | Poll status `ended` | Tells the agent to stop polling, carries `ended_by`, and says not to reopen uninvited after a user end. | cli.js `createEndedNextStep` | S |
| F-020 | Poll status `browser_disconnected` | Returns after the reconnect grace expires, keeps the session resumable, tells the agent to ask the user. | cli.js `createPollOutput`, server.js | S |
| F-021 | Poll status `waiting` | Returned only when `--timeout-ms` elapses; tells the agent to re-run without the flag. | cli.js `createPollOutput` | S |
| F-022 | Poll status `missing` | Raises a `NOT_FOUND` error telling the agent to run `lavish-axi <file>` first. | cli.js `createPollOutput` | S |
| F-023 | Poll typed errors | `LISTENER_ACTIVE` (second poll without takeover, with holder label and age) and `LISTENER_REPLACED` (displaced poll). | cli.js, server.js, README Flags | S |
| F-024 | Poll stderr banner and ticks | Always writes a wait banner to stderr; writes a per-minute tick only when stderr is a TTY. Stdout stays reserved for the final response. | cli.js `startPollWaitReporter` | S |
| F-025 | Poll signal handling | On SIGINT or SIGTERM prints re-run guidance to stderr and exits 130 or 143. Queued feedback stays safe. | cli.js `onPollSignal` | S |
| F-026 | Poll Herdr chime | Spawns `herdr notification show` once when an indefinite poll enters the waiting state, if both env flags are `1`. Never blocks the poll. | cli.js `notifyHerdrPollReady`, `Lavish-Poll-State` header | S |
| F-027 | `lavish-axi reply <html-file>` | Posts an agent reply and exits 0 only after the server confirms, so the board stops showing Working. | cli.js `replyCommand`, `postAgentReply` | M |
| F-028 | `reply --agent-reply` / `--agent-reply-file` | Gives the text inline or from file or stdin. Exactly one is required, empty text is refused, 2 MB JSON limit, 10 second receipt timeout. | cli.js `REPLY_VALUE_FLAGS`, `AGENT_REPLY_RECEIPT_TIMEOUT_MS` | S |
| F-029 | `lavish-axi end <html-file>` | Ends a session as the agent, which still allows a plain reopen later (`ended_by: agent`). | cli.js `endCommand`, server.js `/api/end` | S |
| F-030 | `lavish-axi export <html-file>` | Writes one portable HTML file with local assets inlined. Reports bytes, unresolved assets and notices. | cli.js `exportCommand`, export-bundle.js | M |
| F-031 | `export --out <path>` | Chooses the output path instead of `<name>.export.html` beside the source. | cli.js, export-bundle.js `exportFileName` | S |
| F-032 | `lavish-axi share <html-file>` | Publishes the inlined HTML to ht-ml.app (public by default) and prints the URL, site_id and a one-time update_key. | cli.js `shareCommand`, html-app.js | M |
| F-033 | `share --private` | Publishes behind a Lavish-generated password returned once in the output. | cli.js `resolveShareRequest`, share-password.js | S |
| F-034 | `share --password <pw>` | Publishes behind a user-chosen password that is never echoed. Empty or whitespace value is refused. | cli.js `checkedShareFlagValue` | S |
| F-035 | `share --site <id> --update-key <key>` | Republishes an existing page in place with the same URL. Keeps the password unless a password flag is given. | cli.js `updateShareSite` | M |
| F-036 | `share --unpublish --site --update-key` | Replaces the page with a placeholder locked behind a discarded random password (the host cannot delete). Takes no file. | cli.js `unpublishShareSite`, html-app.js `createUnpublishedPageHtml` | M |
| F-037 | `share --token <t>` | Sends an optional bearer token when creating a page. Rejected on republish and unpublish. | cli.js `resolveShareRequest` | S |
| F-038 | Share argument guards | Refuses `--private` with `--password`, a value flag that swallows the next flag, and site ids outside `A-Za-z0-9._-`. | cli.js `shareFlagValue`, `assertShareSiteId`, html-app.js `normalizeSiteId` | S |
| F-039 | Share outcome reporting | Separates a rejected write (4xx) from an unknown outcome, and a 200 with a malformed body from a failure. Suggests only safe re-run commands. | cli.js `createShareSite` etc., html-app.js `hostRejectedShareWrite`, `publishedDespiteError` | M |
| F-040 | `lavish-axi stop` | Shuts down the background server, including same-installation duplicates on other addresses. | cli.js `stopCommand`, `shutdownServerOnPort` | M |
| F-041 | `stop --port <port>` | Stops a server on a non-default port. | cli.js `stopCommand` | S |
| F-042 | `lavish-axi playbook [id]` | Lists playbooks or prints one; unknown id gives a validation error with the known ids. | cli.js `createPlaybookOutput`, playbooks.js | S |
| F-043 | `lavish-axi libraries` | Lists Excalidraw libraries and their item counts, plus skipped files with reasons. | cli.js `createLibrariesOutput` | S |
| F-044 | `libraries --search <text>` | Lists item refs whose ref contains every search word (50 max, then a `more_items` count). | cli.js `LIBRARY_ITEM_LIST_LIMIT` | S |
| F-045 | `libraries --library <id>` | Lists item refs for one library. | cli.js | S |
| F-046 | `lavish-axi design` | Prints design guidance, CDN snippets, router, whiteboard snippet and DaisyUI reference. | cli.js `designCommand`, design-reference.js | M |
| F-047 | `lavish-axi setup hooks` | Installs or repairs SessionStart hooks for Claude Code, Codex, OpenCode (via the AXI SDK) and GitHub Copilot CLI (own JSON hook file). | cli.js `setupCommand`, `installCopilotCliSessionStartHook` | M |
| F-048 | `lavish-axi setup plugin` | Registers the package as an Agent Plugin in VS Code, Cursor and Copilot CLI, reporting each client separately. | cli.js `setupPluginCommand`, plugin.js | M |
| F-049 | `lavish-axi server` | Runs the local server in the foreground (the CLI spawns it detached). | cli.js `serverCommand`, server.js `serve` | L |
| F-050 | `server --port <port>` | Chooses the server port (default 4387). | cli.js `serverCommand` | S |
| F-051 | `server --verbose` | Logs session and watcher events to stderr (same as `LAVISH_AXI_DEBUG=1`). | cli.js, README Flags | S |
| F-052 | `server --also-listen <host>` (repeatable) | Adds more concrete listen addresses; the CLI passes it when replacing a server. | cli.js `flagValues`, README Flags | S |
| F-053 | Per-command `--help` text | Each command has its own help string with usage, rules and examples. | cli.js `createCommandHelp` | M |
| F-054 | Flag parsing forms | Accepts `--flag value`, `--flag=value` and a `--` end marker; first positional arg skips value flags. | cli.js `firstPositionalArg`, `flagValue`, `inspectValueFlag` | S |
| F-055 | Output format and error codes | Prints TOON through the AXI SDK with codes `VALIDATION_ERROR`, `NOT_FOUND`, `SERVER_ERROR`, `UNKNOWN` plus hint lines. | cli.js `AxiError` use (SDK is external) | M |

## 2. Environment variables

| ID | Feature | What it does for the person or agent | Where it lives | Size |
| --- | --- | --- | --- | --- |
| F-056 | `LAVISH_AXI_PORT` | Sets the server port, default 4387. | paths.js `defaultPort`, README | S |
| F-057 | `LAVISH_AXI_HOST` | Pins the bind address; disables automatic Tailscale binding; wildcard values reduce to loopback. | paths.js `bindHost`, README Network binding | M |
| F-058 | `LAVISH_AXI_LINK_HOST` | Sets the host name written into session links when Tailscale MagicDNS is not used. | paths.js `resolveLinkHost` | S |
| F-059 | `LAVISH_AXI_ALLOWED_HOSTS` | Adds Host header names the server accepts (whitespace separated); `*` turns the check off. | paths.js `extraAllowedHosts`, README Allowed hosts | S |
| F-060 | `LAVISH_AXI_STATE_DIR` | Moves all state (default `~/.lavish-axi`). | paths.js `stateDir`, README | S |
| F-061 | `LAVISH_AXI_NO_OPEN` | `1` is the same as `--no-open`. | cli.js `shouldOpenBrowser` | S |
| F-062 | `LAVISH_AXI_DEBUG` | `1` is the same as `server --verbose`. | cli.js `serverCommand` | S |
| F-063 | `LAVISH_AXI_IDLE_TIMEOUT_MS` | Idle self-shutdown delay, default 30 minutes; `0` or `off` disables. | server.js `resolveIdleTimeoutMs` | S |
| F-064 | `LAVISH_AXI_DISCONNECT_GRACE_MS` | Reconnect grace before a poll returns `browser_disconnected`; default 10 s; `0` or `off` never ends the poll. | server.js `resolveBrowserDisconnectGraceMs` | S |
| F-065 | `LAVISH_AXI_HERDR_CHIME` | With `HERDR_ENV=1`, shows a Herdr notification when a poll starts waiting. | cli.js `herdrPollChimeEnabled` | S |
| F-066 | `LAVISH_AXI_DIAGNOSTIC_VIEWPORTS` | Chooses which viewport classes (`mobile`, `compact`, `desktop`) the layout inbox tracks. | layout-warnings.js `resolveDiagnosticViewportClasses` | S |
| F-067 | `LAVISH_AXI_MAX_ATTACHMENT_BYTES` | Per-image cap, default 10 MiB. | attachment-store.js `resolveAttachmentConfig` | S |
| F-068 | `LAVISH_AXI_MAX_ATTACHMENTS_PER_PROMPT` | Image count cap per prompt, default 4. | attachment-store.js | S |
| F-069 | `LAVISH_AXI_MAX_PROMPT_ATTACHMENT_BYTES` | Total image bytes per prompt, default 25 MiB. | attachment-store.js | S |
| F-070 | `LAVISH_AXI_ATTACHMENT_TTL_MS` | Expiry for unreferenced attachments, default 7 days; `0` or `off` disables. | attachment-store.js | S |
| F-071 | `LAVISH_AXI_MAX_ATTACHMENT_DISK_MB` | Total attachment disk cap, default 512 MiB; `0` or `off` disables. | attachment-store.js | S |
| F-072 | `LAVISH_AXI_EXPORT_MAX_ASSET_BYTES` | Per-asset inline cap for export and share, default 10 MB. | export-bundle.js, README | S |
| F-073 | `LAVISH_AXI_EXPORT_MAX_BUNDLE_BYTES` | Whole-bundle inline cap, default 25 MB. | export-bundle.js, README | S |
| F-074 | `LAVISH_AXI_HTML_APP_API_URL` | Points `share` at another backend; default `https://api.ht-ml.app`. | html-app.js `htmlAppApiUrl`, share-doc | S |
| F-075 | `LAVISH_AXI_HTML_APP_TOKEN` | Optional bearer token for creating pages. | html-app.js, share-doc | S |
| F-076 | `LAVISH_AXI_TELEMETRY` | `0`, `false` or `off` turns telemetry off. | telemetry.js `resolveTelemetryConfig` | S |
| F-077 | `LAVISH_AXI_UMAMI_WEBSITE_ID` | Enables telemetry in a source build. | telemetry.js | S |
| F-078 | `LAVISH_AXI_UMAMI_HOST` | Overrides the telemetry host. | telemetry.js | S |
| F-079 | Build-time `LAVISH_AXI_BUILD_VERSION`, `LAVISH_AXI_BUILD_UMAMI_HOST`, `LAVISH_AXI_BUILD_UMAMI_WEBSITE_ID` | Values inlined by the build for the version handshake and baked-in telemetry. | cli.js `VERSION`, telemetry.js, scripts/build.js | S |
| F-080 | `HERDR_ENV` | Herdr session marker; must equal `1` for the chime. | cli.js | S |
| F-081 | `CODEX_SANDBOX`, `CODEX_THREAD_ID` | Presence of either switches poll guidance to the Codex attached-turn warning. | cli.js `detectInvokingAgent` | S |
| F-082 | `HOME` | Home dir used for hook and plugin setup (falls back to the OS home). | cli.js `resolveHookHomeDir` | S |
| F-083 | `COPILOT_HOME` | Copilot CLI config dir for the hook file and plugin check. | cli.js `resolveCopilotHookDir` | S |
| F-084 | `XDG_CONFIG_HOME`, `APPDATA` | Locate the VS Code user settings file on Linux and Windows. | plugin.js `resolveVsCodeSettingsFile` | S |
| F-085 | `INSTALL_INTERNAL_SKILLS` | Makes `npx skills add --list` show the internal brand skill. Read by the skills tool, not by lavish-axi. | README Quick Start | S |

## 3. Server and process lifecycle

| ID | Feature | What it does for the person or agent | Where it lives | Size |
| --- | --- | --- | --- | --- |
| F-086 | Detached background server | The CLI spawns one detached server, waits for `/health`, and reuses it; spawn cwd is the state dir. | cli.js `startServer`, `createServerSpawnOptions`, bin/lavish-axi-server.js | M |
| F-087 | `/health` endpoint | Reports `ok, app, version, state_id, process_id, state_dir, hosts, requested_hosts, listeners`, plus `network_stale` and `network_warning`. 503 until ready. | server.js `/health` | M |
| F-088 | `/health?reconcile_network=1` | Forces a network re-check and bind retry. | server.js `reconcileNetwork` | S |
| F-089 | Version handshake | Replaces only a server older than the CLI (numeric compare); adopts an equal or newer one. | cli.js `shouldRestartServer`, `isServerOlderThanCli` | M |
| F-090 | Local-build force restart | A source-checkout CLI replaces a server of any version. | cli.js `shouldForceRestartForLocalBuild` | S |
| F-091 | One server per port | Probes configured host, loopback and local interface addresses in parallel and adopts the first owned server. | cli.js `findRunningServer`, `ensureServer` | L |
| F-092 | Installation identity | `state_id` (hash of state file path) decides ownership; another installation is never used, replaced or stopped, and gives `SERVER_ERROR`. | cli.js `isOwnedServer`, paths.js `stateId` | M |
| F-093 | Duplicate retirement | Shuts down other owned servers on the same port over `POST /shutdown`, after the kept one serves their addresses. | cli.js `stopDuplicateServers`, `hostsToServe` | M |
| F-094 | Inherited listen hosts | Every replacement keeps all previously requested addresses via `--also-listen`; drops only IPs gone from local interfaces. | cli.js `inheritedListenHosts` | M |
| F-095 | Missing-host replacement | Replaces a server that does not serve the CLI's explicit `LAVISH_AXI_HOST`, once; then errors. | cli.js `missingServerHosts`, `missingHostsError` | M |
| F-096 | Loopback-first binding | Binds loopback first as the port lock, retries other addresses (100/250/500 ms), always includes loopback. | server.js `serve`, paths.js `resolveListenHosts` | L |
| F-097 | Pending bind recovery | A failed address is retried for the life of the process (1 s up to 30 s) and clears `network_warning` when it binds. | server.js `pendingBinds`, `BIND_RECOVERY_DELAYS_MS` | M |
| F-098 | Wildcard refusal | `0.0.0.0` and `::` are never listened on, and names resolving to them are refused. | paths.js `isWildcardHost`, `resolveConcreteListenHosts` | S |
| F-099 | Unresolved host kept | A host name that does not resolve now is kept and retried instead of dropped. | paths.js `keepUnresolved` | S |
| F-100 | `POST /shutdown` | Graceful stop with optional `reload_key` and `reason` (`upgrade`, `local-build`, `stop`). | server.js, cli.js `requestShutdown` | S |
| F-101 | Exact-PID kill fallback | For a pre-handshake server, signals only a Lavish PID found listening on the exact address and port (via `lsof`). | cli.js `killLavishListener`, `shouldKillProcessOnPort` | M |
| F-102 | Idle self-shutdown | Stops after the last session ends with nothing connected, or after the idle timeout with no browser or poll connections. | server.js, README Server cleanup | S |
| F-103 | Shutdown cause log | Each shutdown records a log-only cause, separate from the user-facing reason. | server.js `shutdown`, inv Process model | S |
| F-104 | Server log file | Detached output is appended with UTC timestamps to `server.log` in the state dir, including uncaught exceptions (exit 1). | server-log.js, bin/lavish-axi-server.js | S |
| F-105 | Health probes without fetch | Probes use `node:http` and destroy the socket on every exit. | cli.js `fetchHealth`, server.js `probeLavishHealth` | S |
| F-106 | Live-event WebSocket | `/events/:key` carries reload, presence, chat-sync, layout-warnings, ended and chrome-reload events, with a 30 s ping/pong that drops dead sockets. | server.js `LIVE_EVENT_HEARTBEAT_MS` | L |
| F-107 | Legacy SSE handoff | An old EventSource client gets one `chrome-reload` and the response ends so it moves to WebSocket. | server.js GET `/events/:key` | S |
| F-108 | Session store | `state.json` keyed by sha256 prefix of the canonical file path; whole-file read and write per operation under one async mutex. | session-store.js, async-mutex.js | L |
| F-109 | Canonical session identity | Paths resolve through `realpath`, so two paths to one file are one session. | session-store.js `canonicalFile`, `sessionKey` | S |
| F-110 | File watcher | `chokidar` watches the artifact file (or its directory with the opt-in) and emits `reload` with a 100 ms debounce, 900 ms while a layout fix batch is queued. | server.js `RELOAD_DEBOUNCE_MS`, `BATCH_RELOAD_DEBOUNCE_MS` | M |
| F-111 | Session listing | Home output lists non-ended sessions with pending prompt count and the listener label from `/health`. | cli.js `visibleSessions` | S |
| F-112 | Attachment sweep schedule | Runs at startup and hourly, reference-aware. | server.js `ATTACHMENT_SWEEP_INTERVAL_MS`, attachment-store.js | M |
| F-113 | Server routes inventory | `/`, `/health`, `/shutdown`, `/api/sessions`, `/api/poll`, `/api/end`, `/api/:key/{prompts,layout-diagnostics,layout-warnings,layout-warnings/queue,layout-warnings/dismiss,artifact-failures,end,agent-reply,export,share,chrome-loads/begin,artifact-loads/begin,mermaid-sources,whiteboard-channel,whiteboard/:index,whiteboard/:index/feedback-files,attachments,attachments/:id}`, `/api/whiteboard-libraries`, `/session/:key`, `/artifact/:key[/...]`, `/events/:key`, `/chrome-client.js`, `/chrome.css`, `/sdk.js`, `/design/:asset`, `/whiteboard-frame`, `/whiteboard-assets/*`. | server.js route table | L |
| F-114 | Landing page at `/` | Serves a small landing HTML page. | server.js `createLandingHtml` | S |

## 4. Review page (browser UI)

| ID | Feature | What it does for the person or agent | Where it lives | Size |
| --- | --- | --- | --- | --- |
| F-115 | Chrome page and sandboxed artifact iframe | `/session/:key` shows a top bar, the artifact in an iframe, and a Conversation panel. | server.js `createChromeHtml` | L |
| F-116 | Top bar brand | Shows "Lavish Editor". | server.js `createChromeHtml` | S |
| F-117 | Annotate switch | Toggles annotate and explore mode; `aria-pressed`; tooltip names the shortcut. | server.js, chrome-client.js `toggleAnnotationMode` | S |
| F-118 | Sidebar toggle | Hides or shows the Conversation panel; counts queued notes or marks an unseen reply while hidden; remembered in `localStorage`. | chrome-client.js `#sidebarToggle`, README Feedback controls | S |
| F-119 | Overflow menu | Holds path copy, reload, DOM snapshot, export, publish and end actions. | server.js `#moreMenu` | S |
| F-120 | Menu: copy path | Shows the file path (head and tail) and copies it. | chrome-client.js `copyFilePath` | S |
| F-121 | Menu: Reload artifact | Reloads the iframe through the recovery path. | chrome-client.js `reloadArtifact` | S |
| F-122 | Menu: Copy DOM snapshot | Copies the SDK's text DOM outline to the clipboard. | chrome-client.js `copyDomSnapshot` | S |
| F-123 | Menu: Export standalone HTML | Downloads the inlined export from `/api/:key/export`. | chrome-client.js `exportArtifact` | S |
| F-124 | Menu: Publish link | Opens the publish dialog for ht-ml.app. | chrome-client.js `openShareDialog` | S |
| F-125 | Menu: End session | Ends the session as the user (`ended_by: user`). | chrome-client.js `endSession` | S |
| F-126 | Publish dialog | Explains third-party hosting, offers "Generate a password" and a password field, then shows URL, password, site ID and update key each with a copy button. | server.js `#shareDialog`, chrome-client.js `publishShare` | M |
| F-127 | Conversation panel | One scrollable log of sent bubbles and queued bubbles above a sticky composer. | server.js, chrome-client.js | L |
| F-128 | Composer | Textarea "Write a message for the agent...", image attach button and chips, notice line. | chrome-client.js `chatInput`, `createChatAttachmentsController` | M |
| F-129 | Send to Agent | Sends all queued prompts plus the composer message; waits up to 5 s for a DOM snapshot, then sends without it. | chrome-client.js `sendQueued` | L |
| F-130 | Send & End | Sends queued prompts and ends the session atomically; holds one terminal batch and survives reload. | chrome-client.js, server.js `/api/:key/prompts` `endSession`, README Feedback controls | L |
| F-131 | Terminal batch recovery | A failed Send & End retries the same batch; a 413 retries once without the snapshot; 400 and 409 cancel the reservation and restore editing. | README Feedback controls, chrome-client.js | M |
| F-132 | Empty-send hint | Empty Send shows "Nothing queued in this tab." plus the take-over note. | chrome-client.js `hideSendHint`, server.js `#sendHint` | S |
| F-133 | Queued note bubbles | Unsent notes show as dashed bubbles ("Queued") with edit and remove controls and an anchor line. | chrome-client.js, inv Request flow 6 | M |
| F-134 | Queued note editing | Click the bubble to edit in place and scroll the artifact to its element; saving an empty note removes it. | chrome-client.js `editQueuedAnchor` | M |
| F-135 | Sending state | A note in flight shows "Sending" and cannot be edited; it settles in place on server ack in every tab. | chrome-client.js, inv Request flow 6 | M |
| F-136 | Sent bubbles | Each sent note shows an anchor line (tag, text, cell, node, whiteboard, layout issues), a quoted excerpt and the selector on hover. | chat-messages.js `chatEntryForPrompt`, chrome-client.js `promptAnchor` | M |
| F-137 | Agent reply bubbles | Render a Markdown subset: paragraphs, line breaks, bold lead headings, lists, fenced and inline code, bold, italic, http(s) links. | chat-messages.js `renderChatMarkdown` | M |
| F-138 | Panel summary and dock | Short status: queued count, reply waiting, or agent listening. | chrome-client.js `#panelSummary` | S |
| F-139 | Presence banner | Shows "Your agent is not listening..." when no poll is attached. | server.js `#presenceBanner`, chrome-client.js | S |
| F-140 | Tab take-over banner | Names another open review tab with a "Take over here" button. | server.js `#handoffBanner`, inv passive layout section | M |
| F-141 | Outdated or unreachable banner | "Lavish was updated..." or "not running" banner with "Check and reload" and "Dismiss". | server.js `#outdatedBanner`, chrome-client.js | M |
| F-142 | Ended overlay | After an end, every tab shows "Session ended. Return to your agent to continue." and goes read-only. | server.js `#endedOverlay`, chrome-client.js `markSessionEnded` | S |
| F-143 | Layout gate overlay | Masks the artifact with "Checking layout. One moment." until the first completed audit; "Show anyway" button. | server.js `#layoutGateOverlay` | M |
| F-144 | Boot failsafe | Inline script keeps the gate escape and "Check and reload" working if the client script hangs (15 s). | server.js `CHROME_BOOT_FAILSAFE_JS` | M |
| F-145 | Tab title and icon adoption | The tab shows the artifact `<title>` and first `<link rel=icon>` (data:, http(s):, protocol-relative only), suffixed " · Lavish". | server.js `extractArtifactHead`, chrome-client.js `applyDocumentMeta` | S |
| F-146 | Chrome page frame denial | `/session/:key` answers `X-Frame-Options: DENY` and `frame-ancestors 'none'`. | server.js | S |
| F-147 | Keyboard: composer Enter | Enter sends queued prompts; Shift+Enter inserts a newline. | chrome-client.js | S |
| F-148 | Keyboard: annotation card Enter | Enter queues the annotation; Shift+Enter inserts a newline. | artifact-sdk.js card keydown | S |
| F-149 | Keyboard: annotation card Ctrl/Cmd+Enter | Queues the annotation and sends all queued prompts. | artifact-sdk.js card keydown | S |
| F-150 | Keyboard: annotation card Escape | Closes the card only when it is empty (no text, no attachment). | artifact-sdk.js | S |
| F-151 | Keyboard: queued note edit | Enter saves, Shift+Enter newline, Escape discards the edit. | chrome-client.js, README Keyboard shortcuts | S |
| F-152 | Keyboard: Cmd/Ctrl+I | Toggles annotate and explore mode from chrome or iframe, even inside text fields. Needs the modifier and no Shift or Alt. | artifact-sdk.js `isModeToggleHotkeyEvent`, chrome-client.js | S |
| F-153 | Keyboard: link click in annotate mode | Plain click annotates a link; Ctrl+click (Cmd on macOS) follows it in a new tab. | README Keyboard shortcuts, artifact-sdk.js | S |
| F-154 | Keyboard: global Escape order | Closes whiteboard overlay, then publish dialog, then revisions drawer, then layout drawer, then more menu, then the mobile sheet. | chrome-client.js keydown handler | S |
| F-155 | IME-safe Enter | Enter is ignored during IME composition (`isComposing`, keyCode 229). | chrome-client.js, artifact-sdk.js | S |
| F-156 | Popover dismissal | Menus and drawers close on outside mousedown and on focus leaving. | chrome-client.js | S |
| F-157 | Circular close buttons | Icon-only close buttons use an inline SVG x on `currentColor`. | inv Things to know when editing | S |
| F-158 | Browser storage keys | Per-tab `sessionStorage` for queue, terminal batch, review state, retired drafts, warning selection, sheet state; `localStorage` for panel collapse. | chrome-client.js (`lavish-axi:*` keys) | M |

## 5. Annotation and targets

| ID | Feature | What it does for the person or agent | Where it lives | Size |
| --- | --- | --- | --- | --- |
| F-159 | Element annotation | In annotate mode a click opens a card anchored to the clicked element; hover outlines it. | artifact-sdk.js `showAnnotationCard`, `highlightElement` | L |
| F-160 | Annotation card | Textarea plus image attach, Queue and Cancel; image-only notes are allowed, empty cards are not. | artifact-sdk.js | M |
| F-161 | Text selection annotation | Selecting text in annotate mode opens a card for a `text-range` target. | artifact-sdk.js `textSelectionContext` | M |
| F-162 | Target type `text-range` | Carries selected text, `selector`, `commonAncestorSelector`, and start and end anchors `{selector, path, offset}`. The prompt `selector` names the container only. | artifact-sdk.js, inv Request flow 6 | M |
| F-163 | Target type `table-cell` | Adds `rowLabel`, `columnLabel`, `text`, `selector` for a clicked `td` or `th`; leaves a name out when merged cells make it unprovable. | table-cell.js `tableCellTarget` | L |
| F-164 | Target type `mermaid-node` | For rendered Mermaid SVGs outside `.mermaid`, annotates the whole node with `diagramId`, `nodeId`, `label`, `selector`. | mermaid-node.js, session-store.js `normalizeTarget` | M |
| F-165 | Target type `excalidraw-scene` | Whiteboard feedback target with edit summary, `scenePath`, `previewPath`, `sourceHash`, stats. | whiteboard-core.js `normalizeExcalidrawSceneTarget` | M |
| F-166 | Target type `layout-warnings` | Queued layout fix batch target listing warning ids and targets. | chrome-client.js, layout-warnings.js | M |
| F-167 | Prompt tags | Built-in tags: `text`, `message` (composer), `layout-warnings`, `whiteboard`, `mermaid-node`, plus element tag names and author tags. | artifact-sdk.js, chrome-client.js | S |
| F-168 | Prompt object shape | `uid, prompt, selector, tag, text, target, attachments` plus internal queue key (stripped before send) and chrome-minted `prompt_id`. | artifact-sdk.js `queuePrompt`, chat-messages.js | M |
| F-169 | Selector generation | Builds a CSS path that must match exactly one element; climbs past five levels, uses `localName`, honors unique ids only. | artifact-sdk.js `selector()` | M |
| F-170 | Interactive control exemption | Native controls and ARIA widget roles (`button, checkbox, combobox, menuitem, menuitemcheckbox, menuitemradio, option, radio, switch, tab, treeitem`) are not annotated. | artifact-sdk.js `isNativeInteractiveControl` | M |
| F-171 | Link annotation rules | A link annotates unless it carries a widget role or sits inside a widget. | artifact-sdk.js | S |
| F-172 | Annotate vs explore mode | Annotate mode shows a default cursor and highlights; explore mode behaves like the plain page. | artifact-sdk.js `setAnnotationMode` | S |
| F-173 | Page default mode | `data-lavish-annotate="off"` on `<html>` starts in explore mode; toolbar override persists across reloads. | artifact-sdk.js, inv Things to know 220 | S |
| F-174 | Queued anchor reopen | Clicking an element with a queued note reopens that note; Mermaid node notes reopen too. | artifact-sdk.js `rememberQueuedAnchor`, `queuedAnchorFor` | M |
| F-175 | Reveal element | Scrolls to and flashes an element (used by queued bubbles and layout Reveal), 2.4 s marker. | artifact-sdk.js `revealElement` | S |
| F-176 | Text highlight overlay | Draws highlight rects for the selected range inside a shadow root. | artifact-sdk.js `highlightTextRange` | S |
| F-177 | DOM snapshot | `snapshot()` returns an indented `uid tag "text"` outline (depth 6) sent with feedback as `dom_snapshot`. | artifact-sdk.js `snapshot` | S |
| F-178 | Mermaid pan and zoom | Outside `.mermaid`, drag pans and wheel zooms the SVG viewBox in explore mode; frozen in annotate mode. | artifact-sdk.js, inv Things to know 208 | M |
| F-179 | Shadow-root UI | SDK overlays live in a shadow root and `data-lavish-ui` nodes are excluded from annotation and audit. | artifact-sdk.js `ensureShadow` | S |
| F-180 | Queue key replacement | Unsent prompts with the same derived key replace each other (question, radio group, checkbox, field). | artifact-sdk.js `deriveLavishQueueKey` | M |

## 6. Page API for artifact authors

| ID | Feature | What it does for the person or agent | Where it lives | Size |
| --- | --- | --- | --- | --- |
| F-181 | `window.lavish.queuePrompt(prompt, options)` | Queues one prompt for the agent. Options: `element`, `uid`, `selector`, `tag`, `text`, `target`, `data` (JSON appended as "Context data"), `queueKey`, `attachments`. | artifact-sdk.js `queuePrompt` | M |
| F-182 | `window.lavish.sendQueuedPrompts()` | Sends everything queued right away. | artifact-sdk.js | S |
| F-183 | `window.lavish.endSession()` | Asks the chrome to end the session. | artifact-sdk.js | S |
| F-184 | `window.lavish.getQueuedPrompts()` | Stub that always returns an empty array. | artifact-sdk.js | S |
| F-185 | `window.lavish.setStatus(message)` | Posts `lavish:status`. No chrome handler was found in `chrome-client.js` or `server.js`, so it looks inert. | artifact-sdk.js | S |
| F-186 | `window.lavish.setDocumentMeta({title, icon})` | Updates tab title (trimmed to 120) and icon (SVG data URL up to 8192 chars); `null` restores; omitted field unchanged. | artifact-sdk.js `setDocumentMeta`, README Live tab title | S |
| F-187 | `window.lavish.snapshot()` | Returns the DOM outline string. | artifact-sdk.js | S |
| F-188 | `data-lavish-action` | Marks a custom clickable element as a feedback control: not annotated, pointer cursor. | artifact-sdk.js `isLavishAction` | S |
| F-189 | `data-lavish-question` | Groups a question; replaces earlier unsent answers for it; scopes review-state restore of control values. | artifact-sdk.js, playbooks.js input | S |
| F-190 | `data-lavish-annotate="on\|off"` | Sets the page default annotation mode on `<html>`. | artifact-sdk.js | S |
| F-191 | `data-lavish-live-reload-root` and `<meta name="lavish-live-reload" content="root">` | Makes the watcher reload on sibling asset changes. | server.js, README Live reload | S |
| F-192 | `<script type="application/json" data-lavish-revisions>` | Declares revision entries `{id, label, timestamp, summary}` for the legend. | artifact-revisions.js `parseRevisionRegistry` | M |
| F-193 | `data-lavish-revision="<id>"` | Marks blocks changed or added in that revision. | artifact-revisions.js `collectRevisionMarks` | S |
| F-194 | `data-lavish-ui` (internal) | Marks Lavish-owned UI that annotation and the layout audit must skip. | artifact-sdk.js `isLavishUi` | S |
| F-195 | `.mermaid` container class | Mermaid diagrams inside it become embedded whiteboards. | artifact-sdk.js, mermaid-source.js | S |
| F-196 | `window.lavish` is the only global | The SDK is one `<script src="/sdk.js?key=...">` appended to `<body>`; the file otherwise stays byte-identical. | html-transform.js `injectLavishSdk`, server.js `/sdk.js` | S |
| F-197 | Artifact to chrome messages | `lavish:queuePrompt, sendQueuedPrompts, endSession, status, documentMeta, snapshot, scroll, reviewState, reviewDraftUnrestorable, annotationMode, toggleAnnotationMode, editQueuedAnchor, uploadAttachment, layoutDiagnostics, artifactAssetFailure, revisions, suspendWhiteboard, resumeWhiteboard`; each stamped with the load token. | artifact-sdk.js `postArtifactMessage`, chrome-client.js message handler | M |
| F-198 | Chrome to artifact messages | `lavish:setAnnotationMode, attachmentResult, requestSnapshot, restoreScroll, restoreReviewState, revealElement, queuedAnchors, annotateElement, requestLayoutDiagnostics`. | artifact-sdk.js message listener | M |
| F-199 | Feature detection contract | Authors are told to use `window.lavish?.setDocumentMeta?.(...)` because the API is absent outside Lavish. | README, design-reference.js `tab_meta` | S |

## 7. Conversation, presence and delivery receipts

| ID | Feature | What it does for the person or agent | Where it lives | Size |
| --- | --- | --- | --- | --- |
| F-200 | Server-owned transcript | Every accepted prompt becomes a bounded user chat entry; the server renders agent Markdown to HTML. | chat-messages.js `serializeChat`, session-store.js | L |
| F-201 | Transcript bound | Keeps newest chat up to 5 MiB of stored JSON; evicted ids move to `chat_ack_ids`. | chat-messages.js `boundStoredChat` | M |
| F-202 | Idempotent send by `prompt_id` | The chrome mints ids; a reload after a lost response recognizes an accepted note and does not resend. | chat-messages.js `normalizePromptId`, session-store.js `queuePrompts` | M |
| F-203 | `chat_revision` sync | Lets the chrome accept an authoritative replacement transcript and reject stale ones. | chat-messages.js `serializeChatSync` | M |
| F-204 | Agent presence states | `waiting`, `listening`, `working` come from the server over the live stream. | server.js `computePresence`, inv Request flow 8 | M |
| F-205 | Agent presence modes | `agent-listener`, `external-listener` (owner label), `agent-busy`, `waiting-on-captain`. | server.js, chrome-client.js | M |
| F-206 | Feedback queued while agent busy | Feedback is accepted and stored for the next poll even when nothing listens. | session-store.js `queuePrompts` | M |
| F-207 | Destructive take with restore | `takeFeedback` clears the batch; a poll that disconnects restores prompts (prepended), snapshot and failures. | session-store.js `takeFeedback`, `restoreClosedFeedback`, inv Request flow 7 | L |
| F-208 | Exclusive poll ownership | One poll per session via `activePolls` with a serialized claim lock. | server.js `pollOwnershipLock` | M |
| F-209 | Receipt: Seen | Each sent note gets a Seen stamp (`delivered_at`, `delivered_seq`) when a poll takes it, assigned by position under the lock. | session-store.js `takeFeedback`, chat-messages.js `stampDelivered`, acks | M |
| F-210 | Receipt: Working | The first artifact file change after delivery stamps `working_at`. | session-store.js `markWorking`, acks | S |
| F-211 | Receipt: Done | An agent reply stamps `done_at` on every delivered, unanswered note. | session-store.js `addAgentReply` | S |
| F-212 | Receipt row UI | Three emoji (👀 Seen, 🛠️ Working, ✅ Done) light in turn; greyed until stamped; labels and times in title and aria-label. | chrome-client.js, acks UI | M |
| F-213 | Pre-delivery reason line | Before Seen the row says no agent is listening, agent busy, or delivering. | chrome-client.js `refreshUnseenReceipts`, acks | S |
| F-214 | Receipt restore rules | A closed-poll restore deletes only that take's stamps; a refused restore also removes them. | session-store.js `restoreClosedFeedback`, acks | M |
| F-215 | Receipts across reopen | `closed_delivery_seq` stops Working and Done from landing on notes delivered before an end. | session-store.js `#upsertSessionLocked`, acks | S |
| F-216 | Pre-receipt transcripts | Old sessions mark entries `receipt: "none"` and show no receipt row. | chat-messages.js `markPreReceipt`, acks | S |
| F-217 | Session end tracking | `ended_by` is `user` or `agent`; open tabs go read-only; later prompts are refused. | session-store.js `endSession`, server.js | M |
| F-218 | User-end reopen guard | A plain open after a user end refuses; `reopen: true` revives it. | server.js `/api/sessions` | S |
| F-219 | Final batch end signal | The last feedback batch before an end carries `session_ended` and `ended_by`, so `next_step` says stop polling. | cli.js `createFeedbackNextStep` | S |
| F-220 | Reconnect grace | Losing the last review socket starts a timer; expiry releases the poll as `browser_disconnected`. | server.js `resolveBrowserDisconnectGraceMs` | M |
| F-221 | Agent reply route | `POST /api/:key/agent-reply` returns `sent`; the reply clears the Working state. | server.js | S |
| F-222 | Fatal artifact failures | `artifact-unavailable` and `artifact-asset-unavailable` mark the session feedback and arrive as `artifact_failures` (max 20). | server.js `/api/:key/artifact-failures`, session-store.js | M |
| F-223 | Delivered attachment grace | Delivered attachment ids stay referenced for a grace window so agents can still read the paths. | session-store.js `MAX_DELIVERED_ATTACHMENTS`, attachment-store.js | S |
| F-224 | Poll wake-path rules | Fixed guidance on foreground polling, background-job limits and no `nohup`; Codex gets an extra warning. | cli.js `POLL_WAKE_PATH_RULES`, `pollExecutionGuidance` | S |
| F-225 | `next_step` text per response | Every output carries tailored next-step guidance (whiteboard, layout, attachment, failure and end notes). | cli.js `createFeedbackNextStep` | M |

## 8. Live reload and state preservation

| ID | Feature | What it does for the person or agent | Where it lives | Size |
| --- | --- | --- | --- | --- |
| F-226 | Artifact file live reload | The iframe reloads whenever the watched file changes. | server.js watcher, chrome-client.js `replaceArtifactFrame` | M |
| F-227 | Directory live reload (opt-in) | Watches the artifact directory, excluding `.git`, `node_modules`, `dist`, `build`, `.lavish-axi`. | server.js | S |
| F-228 | Scroll restore | The SDK reports scroll; the chrome replays it after reload. | artifact-sdk.js `lavish:scroll`, `lavish:restoreScroll` | S |
| F-229 | Review state restore | Replays an open card's unsent text and `data-lavish-question` control values, setting values without firing events. | artifact-sdk.js `restoreReviewState`, chrome-client.js | M |
| F-230 | Review state persistence | The reported state is saved in tab `sessionStorage` and survives a full page reload. | chrome-client.js `lavish-axi:review-state:<key>` | S |
| F-231 | Draft retirement | A stored draft is retired only after two revisions report its selector missing; text goes to the conversation panel as "Unsent annotation". | chrome-client.js `keepRetiredDraft`, artifact-sdk.js `REVIEW_DRAFT_ANCHOR_SETTLE_MS` | M |
| F-232 | Retired draft store | Retired drafts are kept verbatim under `lavish-axi:retired-drafts:<key>` and never trimmed. | chrome-client.js | S |
| F-233 | Queue persistence per tab | The unsent queue survives reload in the same tab; it is not shared across tabs. | chrome-client.js `lavish-axi:queued:<key>` | M |
| F-234 | Annotation mode persistence | The reviewer's mode choice persists across artifact reloads. | chrome-client.js | S |
| F-235 | Server-driven chrome reload | On upgrade, the one session being opened reloads itself; other tabs get `chrome-outdated` banners. | server.js `shutdown`, chrome-client.js | M |
| F-236 | Shutdown banner copy by reason | Banner text depends on `upgrade`, `local-build`, `stop` or none. | chrome-client.js, server.js `SHUTDOWN_REASONS` | S |
| F-237 | Health-gated reloads | Every reload or recovery control probes `/health` first with an abort timeout and restores its button. | chrome-client.js `checkServerThenReload` | M |
| F-238 | Unreachable server banner | After 5 failed socket reconnects the chrome shows the banner; dismissal sticks until recovery. | chrome-client.js `LIVE_EVENT_UNREACHABLE_FAILURES` | S |
| F-239 | Artifact load handoff | A server-issued single-reviewer token stored in `session.artifact_load`; typed `superseded`, `no-handoff`, `out-of-order`. | server.js `/api/:key/artifact-loads/begin`, session-store.js `beginArtifactLoad` | L |
| F-240 | Load retry and failure card | Retries a failed first load (1, 3, 8, 20 s) then shows a failure card; `superseded` never retries. | chrome-client.js `ARTIFACT_LOAD_RECOVERY_DELAYS_MS` | M |
| F-241 | Revisions legend | Top-bar button with a drawer listing up to 6 rounds with swatch, label, time, summary and a Reveal stepper. | artifact-revisions.js, chrome-client.js, server.js `#revisionsDrawer` | L |
| F-242 | Revision swatch design | Each round differs by colour, border style and fill pattern. | artifact-revisions.js `revisionPalette` | S |
| F-243 | Layout-fix reload coalescing | While a fix batch is outstanding, reloads debounce 900 ms. | server.js `BATCH_RELOAD_DEBOUNCE_MS` | S |

## 9. Layout checks

| ID | Feature | What it does for the person or agent | Where it lives | Size |
| --- | --- | --- | --- | --- |
| F-244 | In-iframe layout audit | After fonts and finite animations settle, finds severe failures from rendered evidence; fails open. | artifact-sdk.js (audit block near line 1330 onward) | L |
| F-245 | Audit rule `page-horizontal-overflow` | Reports a page that scrolls sideways with material content past the viewport. | artifact-sdk.js, layout-warnings.js `RULE_DESCRIPTIONS` | M |
| F-246 | Audit rule `clipped-text` | Rendered text fragments cross their container edge. | artifact-sdk.js `classifySevereTextOverflow` | M |
| F-247 | Audit rule `clipped-control` | A required control is cut off by its container. | artifact-sdk.js | M |
| F-248 | Audit rule `viewport-unreachable-control` | A required control sits outside the viewport. | artifact-sdk.js | M |
| F-249 | Audit rule `viewport-unreachable-content` | Rendered text sits outside the viewport. | artifact-sdk.js | M |
| F-250 | Audit rule `overlapping-text` | An opaque static sibling nearly fully covers text. | artifact-sdk.js | M |
| F-251 | Audit exclusions | Ignores ellipsis and line clamp, visually hidden text, scrollers, masks, decorative overlap, diagrams and SVG, and motion; needs the same root in two samples. | artifact-sdk.js, inv Things to know 227 | M |
| F-252 | Audit completeness flag | A failed run publishes `complete: false` with no findings, never an empty pass. | artifact-sdk.js | S |
| F-253 | Viewport classes | `mobile` up to 640 px, `compact` up to 1024 px, `desktop` above. | layout-warnings.js `viewportClassFor` | S |
| F-254 | Warning fingerprint | sha256 prefix of rule, normalized target and viewport class; magnitude excluded. | layout-warnings.js `layoutWarningFingerprint` | S |
| F-255 | Warning statuses | `open, queued, recurring, unverified, reopened, resolved, dismissed, obsolete` with labels (Open, Queued for fix, Still present, Unverified, Returned, Resolved, Dismissed, Obsolete). | layout-warnings.js | M |
| F-256 | Warning lifecycle engine | Pure functions apply passes; clears only on a newer revision plus a complete pass at the same viewport class. | layout-warnings.js `applyDiagnosticPass` | L |
| F-257 | Layout issues button | Top-bar button with unresolved count, hidden when nothing is unresolved. | server.js `#warningsButton`, chrome-client.js | S |
| F-258 | Layout issues drawer | Lists severity, explanation, viewport, target, last seen and state per issue with a select box. | chrome-client.js, layout-warnings.js `serializeLayoutWarnings` | M |
| F-259 | Drawer actions | Select all, per-issue Reveal and Dismiss, "Queue selected fixes". | server.js `#warningsDrawer` | M |
| F-260 | Queue selected fixes | Turns selected issues into one `layout-warnings` prompt (max 50 per prompt); not repeatable while outstanding. | server.js `/api/:key/layout-warnings/queue`, layout-warnings.js | M |
| F-261 | Dismiss per revision | Dismissal applies to the current revision only. | server.js `/api/:key/layout-warnings/dismiss` | S |
| F-262 | Obsolete viewport marking | A warning whose viewport class leaves the configured set is marked obsolete. | layout-warnings.js | S |
| F-263 | Passive detection | Diagnostic reports never emit `feedback` and never wake a poll. | server.js `/api/:key/layout-diagnostics`, inv | M |
| F-264 | Warning cap and history | Keeps up to 200 stored warnings and bounded history (20 stored, 10 shown). | layout-warnings.js constants | S |
| F-265 | Open-time layout gate | Masks the artifact until the first completed client audit; 12 s max hold; "Show anyway" bypass. | server.js `CHROME_LAYOUT_GATE_MAX_HOLD_MS`, chrome-client.js | M |
| F-266 | Self-paint warning | Render-free check for a missing explicit page background; returns `self_paint_warning` on open, export and share. | self-paint.js `analyzeSelfPaint`, cli.js | M |
| F-267 | Layout warning routes | `GET /api/:key/layout-warnings` serves the inbox; the chrome bootstraps from `initialLayoutWarnings` and live `layout-warnings` events. | server.js | S |

## 10. Images and attachments

| ID | Feature | What it does for the person or agent | Where it lives | Size |
| --- | --- | --- | --- | --- |
| F-268 | Accepted image types | PNG, JPEG, WebP, verified by magic bytes; the `Content-Type` header is ignored. | attachment-store.js `ACCEPTED_IMAGE_MIME`, `detectImageType` | S |
| F-269 | Attach by paste, drop or picker | Works in the composer and in the annotation card; shows chips with upload, remove, retry and error states. | chrome-client.js `createChatAttachmentsController`, artifact-sdk.js | L |
| F-270 | Paste planning | Keeps pasted text with images, treats a copied file name or path as placeholder, ignores stray non-image flavors. | chrome-client.js `planClipboardPaste`, `transferredFiles` | M |
| F-271 | Mixed drop handling | Accepts images and raises a chip for each unsupported file; document-level drag guard stops navigation away. | artifact-sdk.js `partitionDroppedFiles`, chrome-client.js | M |
| F-272 | Upload route | `POST /api/:key/attachments` reads the raw body, drains oversized bodies then returns 413, same-origin only. | server.js, attachment-store.js `readAttachmentUploadBody` | M |
| F-273 | Content-addressed storage | File id is `<sha256>.<ext>` under `<state>/attachments/<key>/`; duplicates refresh mtime. | attachment-store.js | M |
| F-274 | Metadata sidecar | A `<id>.meta` sidecar stores dimensions. | attachment-store.js | S |
| F-275 | Thumbnail route | `GET /api/:key/attachments/:id` streams the image for chips and bubbles. | server.js `statAttachmentForServe` | S |
| F-276 | Delete route | `DELETE /api/:key/attachments/:id` is reference counted and returns `referenced` when still used. | server.js | S |
| F-277 | Server-side ref resolution | A prompt carries only `id` and `name`; path, mime, bytes and dimensions are re-derived from disk, all-or-nothing, else HTTP 400. | session-store.js `resolvePromptAttachments`, `boundAttachmentRefs` | M |
| F-278 | Poll attachment payload | Agents receive `attachments[]` with absolute `path`, `id`, mime and dimensions. | cli.js `createFeedbackNextStep`, session-store.js | S |
| F-279 | Per-image, per-prompt and per-count caps | 10 MiB, 25 MiB, 4 images by default; whole batch rejected on breach with a visible reason. | attachment-store.js, README Image attachments | S |
| F-280 | Browser abuse guard | 30 uploads per minute, 4 in flight, 256 MiB per page lifetime. | chrome-client.js `UPLOAD_RATE_MAX`, `UPLOAD_MAX_IN_FLIGHT`, `UPLOAD_SESSION_BYTE_QUOTA` | S |
| F-281 | Chrome as upload mediator | The sandboxed iframe cannot reach the server; the chrome relays uploads and binds results to the document by `ATTACHMENT_NONCE`. | chrome-client.js `uploadAttachment`, artifact-sdk.js | M |
| F-282 | Reference-aware sweeper | TTL cleanup (7 days) and disk or object-cap eviction (oldest first, after a 1 hour grace); never removes referenced files; reaps temp and orphan sidecars. | attachment-store.js `sweepAttachments` | L |
| F-283 | Admission control | Uploads reclaim space first, then refuse with 507 when the write would exceed the cap; cost counts 4096-byte blocks. | attachment-store.js `admitAttachmentCharge` | M |
| F-284 | Owner-only permissions | Files `0600`, dirs `0700`, re-asserted on startup of the dir. | attachment-store.js `ensureAttachmentDir` | S |
| F-285 | Thumbnail display rules | Bubbles show at most 4 thumbnails plus a `+N` badge; evicted images show an "Image expired" placeholder. | chrome-client.js | S |
| F-286 | Image-only messages | The composer allows text, images, or both. | chrome-client.js | S |

## 11. Whiteboard (Mermaid and Excalidraw)

| ID | Feature | What it does for the person or agent | Where it lives | Size |
| --- | --- | --- | --- | --- |
| F-287 | Mermaid to Excalidraw view | In the browser, each rendered `.mermaid` diagram becomes an inline editable Excalidraw whiteboard in a sandboxed sibling iframe. | artifact-sdk.js, whiteboard-frame.js, whiteboard-core.js | L |
| F-288 | Native conversion set | Flowchart, sequence, class, ER and state diagrams become editable shapes with Mermaid ids kept. | whiteboard-frame.js (`@excalidraw/mermaid-to-excalidraw`) | L |
| F-289 | Image fallback | Other diagram types become an image the reviewer can draw on. | whiteboard-frame.js, whiteboard-core.js `sceneIsImageFallback` | M |
| F-290 | Click to unlock | Inline frames start locked behind a click-catcher so they do not trap scrolling. | artifact-sdk.js, whiteboard-frame.js | S |
| F-291 | Fullscreen editing | A Fullscreen action reopens the diagram in a chrome overlay; the inline frame parks on `about:blank`. | chrome-client.js `#whiteboardOverlay`, whiteboard-frame.js `#wbFullscreen` | M |
| F-292 | Autosave sidecars | Scenes autosave (debounced) to `<state>/whiteboards/<key>/` per diagram, not in `state.json`; flush before reload. | whiteboard-store.js, server.js PUT `/api/:key/whiteboard/:index` | M |
| F-293 | Source hash staleness | A changed Mermaid source marks the saved scene stale. | mermaid-source.js `mermaidSourceHash` | S |
| F-294 | Re-convert or keep banner | Unmodified scenes silently re-convert; edited scenes offer "Re-convert (discard saved edits)" or "Keep editing saved scene". | whiteboard-core.js `resolveWhiteboardInitAction`, whiteboard-frame.js | M |
| F-295 | Queue feedback | "Queue feedback" exports the scene and a PNG, then queues a `whiteboard` prompt with an edit summary. | whiteboard-frame.js `#wbQueue`, server.js `feedback-files`, whiteboard-store.js | L |
| F-296 | Edit summary diff | Summarizes added, removed, moved, edited shapes and library items against the conversion baseline (40 lines, 200 chars per line). | whiteboard-core.js `summarizeSceneEdits` | L |
| F-297 | Mermaid source extraction | Reads `.mermaid` sources from the file on disk in document order. | mermaid-source.js `extractMermaidSources`, server.js `/api/:key/mermaid-sources` | M |
| F-298 | Source stays authoritative | No scene to Mermaid reverse conversion; the agent edits Mermaid text. | inv Whiteboard | S |
| F-299 | Whiteboard channel token | Short-lived signed token (5 minutes) bound to the session key; chrome accepts only messages from descendants of the artifact frame. | server.js `/api/:key/whiteboard-channel`, chrome-client.js `isArtifactChildWindow` | M |
| F-300 | Whiteboard frame and assets | `/whiteboard-frame` and `/whiteboard-assets/*` serve a bundled Excalidraw, React, converter and fonts with CORS and no-cache headers. | server.js, scripts/build.js | L |
| F-301 | Mermaid label line breaks | Restores `<br>` and `\n` as real line breaks before shapes materialize; recenters bound text. | whiteboard-core.js `restoreMermaidLabelLineBreaks` | M |
| F-302 | Font-aware re-materialize | Converts again after Excalidraw fonts load; repairs saved text metrics expansion-only. | whiteboard-core.js `convertExcalidrawSkeletonsAfterFontsLoad`, `repairSavedSceneTextMetrics` | M |
| F-303 | Theme handling | Theme only via the Excalidraw prop; persisted app state strips `theme` and dark backgrounds. | whiteboard-core.js `sanitizeWhiteboardAppState` | S |
| F-304 | Excalidraw libraries dir | Reads `.excalidrawlib` files from `<state>/excalidraw-libraries/`; caps 10 MB per file, 25 MB and 5000 items total; reports skips. | whiteboard-library-store.js, whiteboard-libraries.js | M |
| F-305 | Library panel and item tracking | Every whiteboard lists library items; dropped items arrive in the edit summary by ref. | whiteboard-libraries.js `toExcalidrawLibraryItems` | M |
| F-306 | `%% lavish-icon <node-id> <library-id>/<item name>` | Shows a flowchart node as a library icon; ignored by Mermaid elsewhere. | whiteboard-libraries.js `parseLibraryIconDirectives`, whiteboard-core.js `prepareLibraryIconSkeletons`, `placeLibraryIcons` | L |
| F-307 | Icon layout spacing | Icon nodes get a 64 px high icon (max 120 px wide) and wider Mermaid spacing on one axis. | whiteboard-core.js `libraryIconMermaidConfig` | M |
| F-308 | Library snapshot versioning | `libraries_version` mismatch marks the scene hash unverified so it re-converts later. | whiteboard-core.js `UNVERIFIED_LIBRARIES_HASH_SUFFIX` | M |
| F-309 | Libraries API | `GET /api/whiteboard-libraries` (same-origin guarded, read only). | server.js | S |
| F-310 | Mermaid pin | `mermaid` for the converter is pinned exactly (11.12.1); the artifact-facing CDN version is separate (11.15.0). | package.json, design-reference.js | S |
| F-311 | Opt-in policy | Whiteboards only when the user asks; inline SVG is the default figure medium. | design-reference.js, playbooks.js diagram | S |

## 12. Export and share

| ID | Feature | What it does for the person or agent | Where it lives | Size |
| --- | --- | --- | --- | --- |
| F-312 | Local asset inlining | Inlines local stylesheets, classic scripts, images, fonts, icons, CSS `url()` and `@import` (depth 8) as inline blocks and data URIs. | export-bundle.js `buildSelfContainedHtml` | L |
| F-313 | Remote refs left as links | No fetching of http(s) URLs; export makes no outbound requests. | export-bundle.js | S |
| F-314 | Confined local reads | Reads stay inside the artifact directory by lexical and realpath checks. | export-bundle.js `guardedRead`, `confineDir` | M |
| F-315 | Legacy `/design/*` inlining | Maps packaged design assets through an injected resolver. | cli.js `resolveDesignAssetPath`, server.js | S |
| F-316 | `file://` redaction | Absolute `file://` URLs not safely inlined become `about:blank`. | export-bundle.js (`file-url-redacted`) | M |
| F-317 | SDK stripping | The injected SDK is never included; `</script>` and `</style>` are escaped in inlined text. | export-bundle.js | S |
| F-318 | Size caps | Per-asset and per-bundle caps (10 MB, 25 MB). | export-bundle.js | S |
| F-319 | Export warnings | Unresolved asset codes (`load-failed`, `outside-root`, `too-large`, unsupported types and others) and notices (`csp-meta`, `file-url-redacted`). | export-bundle.js `splitExportWarnings`, `exportWarningSummaries` | M |
| F-320 | Fragment and CSP handling | Leaves `#a` refs alone; keeps author CSP meta tags and reports them. | export-bundle.js | S |
| F-321 | Export MIME table | Maps extensions (css, js, svg, png, jpg, gif, webp, avif, ico, bmp, fonts, media, vtt, json, txt, pdf) to data URI types. | export-bundle.js `EXT_MIME` | S |
| F-322 | Export HTML parsing | Uses `parse5` for HTML reference rewriting. | export-bundle.js, package.json | L |
| F-323 | Browser export route | `GET /api/:key/export` returns the same inlined HTML. | server.js | S |
| F-324 | Hosted publish | `POST {api}/v1/sites` with `html_content` and optional `password`; needs `url` and `update_key` in the reply. | html-app.js `publishToHtmlApp`, share-doc | M |
| F-325 | Hosted republish | `PUT {api}/v1/sites/{site_id}` authorized by the update key; absent password keeps the current one. | html-app.js `updateHtmlApp`, share-doc | M |
| F-326 | Unpublish placeholder | Placeholder page ("This page has been unpublished...") with `noindex`. | html-app.js `createUnpublishedPageHtml` | S |
| F-327 | Share timeouts | Both requests time out after 30 s. | share-doc, html-app.js | S |
| F-328 | Password generation | One shared generator for CLI and browser flows. | share-password.js | S |
| F-329 | Browser publish route | `POST /api/:key/share` (same-origin guarded) echoes a password only when Lavish minted it. | server.js | M |
| F-330 | No credential storage | Lavish stores neither the password nor the update key. | inv Hosted sharing | S |
| F-331 | CDN lock caveat text | Every "newly private" output warns that a previously public page may stay cached for minutes. | cli.js, inv Hosted sharing | S |
| F-332 | Self-hosting contract | Documented backend contract and a Cloudflare Worker reference. | docs/self-hosting-share.md | S |
| F-333 | Export and share self-paint warning | Both surfaces run the self-paint check. | cli.js | S |

## 13. Agent guidance (help, design, playbooks, skill, hook, plugin)

| ID | Feature | What it does for the person or agent | Where it lives | Size |
| --- | --- | --- | --- | --- |
| F-334 | Visual guidance list | Five rules in the home output (hierarchy, show don't tell, structure, typography, overflow). | cli.js `createHomeOutput` | S |
| F-335 | Playbook router | Instruction that agents MUST open every matching playbook before writing HTML. | playbooks.js `PLAYBOOK_ROUTER_INSTRUCTION` | S |
| F-336 | Playbook `diagram` | Inline SVG default, whiteboard opt-in, one concept per diagram, render-verify rules. | playbooks.js | M |
| F-337 | Playbook `table` | Table vs cards, summary first, overflow and status color guidance. | playbooks.js | S |
| F-338 | Playbook `comparison` | Before/after, option cards, scorecard guidance. | playbooks.js | S |
| F-339 | Playbook `plan` | Goal, approach, risks, open questions structure. | playbooks.js | S |
| F-340 | Playbook `code` | Requires `@pierre/diffs` from esm.sh with a working snippet. | playbooks.js | S |
| F-341 | Playbook `input` | Collecting answers: per-question submit, `data-lavish-question`, tracked batch, optional "Copy all answers" snippet. | playbooks.js | M |
| F-342 | Playbook `explanation` | Narrative explanation of existing systems, PRs, incidents. | playbooks.js | S |
| F-343 | Playbook `slides` | Deliberate presentation guidance. | playbooks.js | S |
| F-344 | Playbook fields | Each playbook has `id`, `use_when`, `choose`, `structure`, `design_rules`, `pitfalls`, `lavish_notes`. | playbooks.js | S |
| F-345 | Design priority rule | Single-sourced order: user's look, then subject project's design system, then Tailwind v4 plus DaisyUI v5 fallback. | design-reference.js `DESIGN_PRIORITY_RULE` | S |
| F-346 | Design output: CDN snippet | Tailwind browser 4.2.4, DaisyUI 5.5.19 and themes CSS from jsDelivr, with URLs and versions. | design-reference.js `DESIGN_CDN_SNIPPET` | S |
| F-347 | Design output: layout safety CSS | Optional snippet for `min-width: 0`, wrapping and media limits. | design-reference.js `LAYOUT_SAFETY_CSS_SNIPPET` | S |
| F-348 | Design output: Mermaid snippet | Theme-aware Mermaid 11.15.0 init that re-renders on theme or OS change. | design-reference.js `MERMAID_CDN_SNIPPET` | M |
| F-349 | Design output: library icon guidance | Syntax, example and notes for `%% lavish-icon`. | design-reference.js | S |
| F-350 | Design output: revision marking | Registry snippet and usage rules. | design-reference.js `REVISION_REGISTRY_SNIPPET` | S |
| F-351 | Design output: tab meta note | Pointer to `setDocumentMeta`. | design-reference.js | S |
| F-352 | Design output: theme usage and DaisyUI reference | 35 themes, default `luxury`, semantic color rules, component groups, modifiers, class references with syntax and notes. | design-reference.js | L |
| F-353 | Installable skill stub | `skills/lavish/SKILL.md` stays a short stub (max 4000 chars) that points at the CLI; includes `$ARGUMENTS` and Hermes metadata. | skill.js `createSkillMarkdown`, scripts/build-skill.js | M |
| F-354 | Skill validator | Checks allowed frontmatter keys, no flow collections, flat string metadata. | skill.js `validateSkillMarkdown`, `ALLOWED_SKILL_FRONTMATTER_KEYS` | M |
| F-355 | Skill freshness check | `build-skill.js --check` fails if the committed skill drifts. | scripts/build-skill.js | S |
| F-356 | Session start hooks | Hooks surface home output (live sessions) at agent session start for Claude Code, Codex, OpenCode (SDK installer) and Copilot CLI (`lavish-axi.json` hook file with bash and powershell commands). | cli.js `installCopilotCliSessionStartHook`, axi-sdk-js | M |
| F-357 | Copilot hook merge | Keeps unmanaged hook entries, replaces managed ones, is idempotent. | cli.js `computeCopilotCliHookUpdate` | S |
| F-358 | Agent Plugin manifest | Root `plugin.json` beside `skills/`; no MCP server. | plugin.json, scripts/build-plugin.js | S |
| F-359 | Plugin: VS Code registration | Adds the package dir to `chat.pluginLocations`; will not rewrite unparseable settings. | cli.js `registerVsCodePlugin`, plugin.js | M |
| F-360 | Plugin: Cursor registration | Links the package into `~/.cursor/plugins/local/lavish-axi` (junction on Windows). | cli.js `registerCursorPlugin`, plugin.js `linkCursorLocalPlugin` | M |
| F-361 | Plugin: Copilot registration | Runs `copilot plugin install <dir>` after checking installed records. | cli.js `registerCopilotPlugin` | M |
| F-362 | Plugin per-client status | Reports `registered`, `current`, `absent`, `manual`, `failed` per client without failing the command. | cli.js `setupPluginCommand` | S |
| F-363 | Poll and reply rules text | Shared rule strings for replies (concise, Markdown only when needed) and Send & End. | cli.js `POLL_AGENT_REPLY_RULE`, `POLL_SEND_AND_END_RULE` | S |
| F-364 | Artifact placement guidance | Tells agents to create artifacts under `.lavish/` and copy assets beside the HTML with relative paths. | cli.js `createHomeOutput` | S |

## 14. Security measures

| ID | Feature | What it does for the person or agent | Where it lives | Size |
| --- | --- | --- | --- | --- |
| F-365 | Host header allowlist | 403 for a missing or unknown `Host`, to stop DNS rebinding. | server.js, paths.js `extraAllowedHosts`, inv Process model | M |
| F-366 | Forwarded host validation | `X-Forwarded-Host` and `X-Forwarded-Proto` are validated against the same list. | server.js | S |
| F-367 | Origin and Referer guard | Mutating routes reject a present foreign Origin or Referer; header-less CLI calls still pass. | server.js middleware | M |
| F-368 | Same-origin only routes | `/prompts`, `/share`, whiteboard writes and attachment upload and delete require a matching origin. | server.js `isSameOriginRequest` | S |
| F-369 | Iframe sandbox | Artifact iframe uses `allow-scripts allow-forms allow-popups allow-popups-to-escape-sandbox allow-downloads` with no `allow-same-origin`. | server.js `createChromeHtml` | S |
| F-370 | CSP sandbox on artifacts | Every `/artifact/*` response carries a matching CSP `sandbox` directive. | server.js | S |
| F-371 | Asset path confinement | Artifact assets resolve inside the HTML file's directory by realpath; symlinks cannot escape. | server.js `resolveArtifactAsset` | M |
| F-372 | HTML file gate | `/api/sessions` and artifact routes refuse non-regular or non-HTML files after realpath. | artifact-path.js `resolveAllowedArtifactFile` | S |
| F-373 | Session key is not a secret | No route treats the key as authorization. | inv Process model | S |
| F-374 | Token-stamped messages | The chrome drops frame messages not stamped with the current artifact load token. | artifact-sdk.js `postArtifactMessage`, chrome-client.js | S |
| F-375 | Escaped user text | User entries render as text; only agent entries become HTML, from a small Markdown subset. | chat-messages.js | S |
| F-376 | Chrome mints `prompt_id` | The iframe never supplies ids. | chrome-client.js | S |
| F-377 | Queued anchor privacy | The iframe learns only selectors of queued notes, never their text. | chrome-client.js `lavish:queuedAnchors` | S |
| F-378 | Single SDK injection | Only one script tag is injected into served artifacts. | html-transform.js | S |
| F-379 | Non-wildcard listening | Never listens on all interfaces; Tailscale binding is the only non-loopback default. | paths.js | S |
| F-380 | Exact-PID signalling | Never signals by port alone; ownership proven by `/health` identity. | cli.js | M |
| F-381 | Attachment hardening | Magic-byte validation, owner-only modes, referenced-file protection, server-side path derivation. | attachment-store.js, session-store.js | M |
| F-382 | Export confinement and redaction | No network, realpath confinement, `file://` redaction. | export-bundle.js | M |
| F-383 | Share safety rules | No clear-password path, empty value refusal, no password placeholders in suggested commands, untrusted echoed `site_id`. | cli.js, html-app.js | M |
| F-384 | Whiteboard route guards | Same-origin write routes with a 20 MB JSON limit; other JSON limit 2 MB. | server.js `isWhiteboardWriteApiPath` | S |
| F-385 | Unauthenticated warning | Binding beyond loopback is documented as exposing an unauthenticated file-serving server. | README Network binding | S |
| F-386 | Store mutex | Every state write takes `store.lock` so reads cannot be lost. | async-mutex.js, session-store.js | M |

## 15. Telemetry

| ID | Feature | What it does for the person or agent | Where it lives | Size |
| --- | --- | --- | --- | --- |
| F-387 | Page view event | Sends one page view per run with the command name, version, platform and arch. | telemetry.js, cli.js `run` | S |
| F-388 | Command event | Sends a `command` event with `status` `success` or `error` (only for thrown errors). | cli.js `run` | S |
| F-389 | No arguments or paths | Payloads exclude arguments, paths, content and prompts; no user id. | telemetry.js | S |
| F-390 | Version skip | `--version` sends nothing. | cli.js `isVersionOnlyArgv` | S |
| F-391 | Opt-out and build config | `LAVISH_AXI_TELEMETRY=0`; host and website id baked at build; source builds send nothing without a website id. | telemetry.js | S |
| F-392 | Best-effort delivery | 1 second timeout, errors swallowed, drained before exit. | telemetry.js `HttpTelemetryClient` | S |
| F-393 | Umami wire format | POSTs `/api/send` with `type: event`, hostname `cli`, title "Lavish Editor CLI". | telemetry.js | S |

## 16. Phone and remote access

| ID | Feature | What it does for the person or agent | Where it lives | Size |
| --- | --- | --- | --- | --- |
| F-394 | Tailscale detection | Finds the `tailscale` binary (PATH and platform install paths), reads `status --json`, needs `BackendState: Running`, takes the IPv4 and MagicDNS name. | tailscale.js | M |
| F-395 | Safe candidate resolution | Only launches candidates that resolve to executable regular files, under one shared timeout. | tailscale.js, inv Process model | S |
| F-396 | Automatic Tailscale listener | With Tailscale up and no `LAVISH_AXI_HOST`, listens on loopback plus the Tailscale IPv4 only. | paths.js `resolveListenHosts` | M |
| F-397 | MagicDNS session links | Session URLs use the MagicDNS name when the Tailscale listener is bound. | paths.js `resolveLinkHost` | S |
| F-398 | Network warnings | Reports `network_warning` in open output and `server.log` when an address cannot bind or MagicDNS is missing. | server.js `currentNetworkWarning` | M |
| F-399 | Network change replacement | A Tailscale identity change reports `network_stale` and triggers one server replacement. | cli.js `ensureServer`, server.js `reconcileNetwork` | M |
| F-400 | Reverse proxy support | Allowed hosts plus forwarded host and proto handling for hosted setups. | server.js, README Allowed hosts | M |
| F-401 | Phone bottom sheet | Below 860 px the artifact fills the screen and the Conversation opens as a bottom sheet over a dock. | chrome.css, chrome-client.js sheet controller | L |
| F-402 | Sheet gestures and controls | Tap or swipe the dock, press the chevron to open; tap the scrim, swipe down, press the chevron or Escape to close. | chrome-client.js | M |
| F-403 | Sheet dock summary | Shows queued count, an unread reply, or listening state; sheet state persists across reloads. | chrome-client.js, README Reviewing on a phone | S |
| F-404 | Visual viewport sync | Sizes the sheet to the visible viewport (`--vv-top`, `--vv-height`) so the keyboard does not cover the composer; honors safe-area insets. | chrome-client.js `syncVisualViewport`, chrome.css | M |
| F-405 | Landscape sheet | In landscape the sheet covers the top bar. | chrome.css | S |
| F-406 | Long disconnect budget | `LAVISH_AXI_DISCONNECT_GRACE_MS` keeps polls alive while a phone sleeps. | server.js | S |
| F-407 | Desktop panel collapse isolation | Collapse never applies at phone width. | chrome-client.js, inv Things to know 219 | S |

## 17. Anything else

| ID | Feature | What it does for the person or agent | Where it lives | Size |
| --- | --- | --- | --- | --- |
| F-408 | Build pipeline | `esbuild` bundles `dist/cli.mjs`, `dist/server.mjs`, chrome assets and `dist/whiteboard/` (Excalidraw, React, fonts). | scripts/build.js | L |
| F-409 | Package contract | Node 22+, ESM, bin `lavish-axi`, files list (`dist`, `plugin.json`, `skills/lavish`, GIF, license, notices, README). | package.json | S |
| F-410 | Packaged design assets route | `/design/:asset` still serves Tailwind and DaisyUI files for old artifacts. | server.js `resolveDesignAssetPath` | S |
| F-411 | HTML SDK injection transform | Appends the SDK script before `</body>`. | html-transform.js | S |
| F-412 | Raw chrome client and CSS | The chrome script and stylesheet are served as raw files, not modules. | server.js `/chrome-client.js`, `/chrome.css` | S |
| F-413 | Chrome icon set | Inline SVG icons for warning, sidebar, more, file, copy, check, refresh, camera, download, globe, exit, chevron. | server.js `chromeIcons` | S |
| F-414 | Windows support | Cursor plugin uses a junction; paths normalize backslashes for display. | plugin.js, cli.js `collapseHomeDirectory` | S |
| F-415 | Release and plugin sync | release-please bumps `plugin.json`; `build-plugin.js --check` guards drift. | scripts/build-plugin.js, release-please-config.json | S |
| F-416 | Third-party notices | Ships a notices file for bundled libraries. | THIRD-PARTY-NOTICES.md | S |
| F-417 | Test suite layout | `node:test` suites in `test/`, plus opt-in browser suites needing `chrome-devtools-axi`. | test/, README Development | L |
| F-418 | Local address helper | Lists local interface addresses for duplicate and replacement logic. | local-address.js | S |
| F-419 | Async mutex | Small promise-based lock used by the store. | async-mutex.js | S |

## Unverified or external

- `axi-sdk-js` supplies TOON encoding, the `update` self-updater, `RESERVED_COMMANDS` and the Claude Code, Codex and OpenCode hook installer. Its internals are not in this repo.
- `src/chrome-client.js` (205 KB), `src/chrome.css` and parts of `src/server.js` were checked by search and by reading the HTML template, not read line by line. Some chrome behaviors are taken from README and invariants.
- `window.lavish.setStatus` posts `lavish:status`; no receiver was found. It may be dead code.
- The audit sampling details (timings, thresholds) in `artifact-sdk.js` were not enumerated.
- `lavish-editor-marketing/`, `task-evidence/` and `test/` were not inspected.

## Counts

| Group | Features |
| --- | --- |
| 1. CLI commands and flags | 55 |
| 2. Environment variables | 30 |
| 3. Server and process lifecycle | 29 |
| 4. Review page (browser UI) | 44 |
| 5. Annotation and targets | 22 |
| 6. Page API for artifact authors | 19 |
| 7. Conversation, presence and delivery receipts | 26 |
| 8. Live reload and state preservation | 18 |
| 9. Layout checks | 24 |
| 10. Images and attachments | 19 |
| 11. Whiteboard (Mermaid and Excalidraw) | 25 |
| 12. Export and share | 22 |
| 13. Agent guidance (help, design, playbooks, skill, hook, plugin) | 31 |
| 14. Security measures | 22 |
| 15. Telemetry | 7 |
| 16. Phone and remote access | 14 |
| 17. Anything else | 12 |
| Total | 419 |
