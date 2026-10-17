# RFC-007 — ewe-companion, the desktop companion

*Status: accepted (owner idea 2026-10-13; the owner took all nine proposed
answers 2026-10-14) · P1 done, P2 working · two new repos: `prj786/ewe-companion`
(daemon, CLI, agent hook relay, later a Tauri window) and
`prj786/ewe-plugin-companion` (the island, plugin id `ewe.companion`) · one
core change in ewe (Plugin API 4: the notification presenter) · opt-in like
every plugin (D1) · the build plan is `ewe-companion/docs/PLAN.md`*

## The idea

A quiet presence at the top of the screen. It knows what the desktop is doing
and tells you only what matters.

It sits in the bar's empty centre. When a Claude Code session in any terminal
wants permission, the island asks you (**Allow · Deny · Always**) and you never
switch back to the terminal. When an agent finishes, a download lands, the disk
fills up or a notification has sat unread since yesterday, it says so once, in
one line, when you are not busy. When the companion is on, it can show
notifications itself instead of the stock banners. When you want something, you
ask it: "how much space is left", "set the accent to teal", "what did Claude
change in ewe/". It answers with the AI you already pay for, a local model, or
no AI at all.

The model is Coucou (github.com/Louis-CFM/coucou: macOS, plus a Tauri port for
Linux), which does the agent half. ewe-companion does that half and adds the
desktop half: ewe owns the desktop, so the companion can use its notifications,
its services and the one file.

**Division of labour (the sentence that prevents scope creep):** the shell
draws, the daemon thinks, the existing tools act. ewe-conf still writes the
file, ewe-sync still syncs, Komble still installs. The companion only **asks,
tells and delegates**. It never builds a second pipeline.

## What the research says (2026-10-13)

**Claude Code hooks** (code.claude.com/docs/en/hooks):

- A `PermissionRequest` hook can answer with
  `hookSpecificOutput.decision.behavior = allow | deny`.
- For **Always**, the hook echoes one of Claude's own `permission_suggestions`
  back as `updatedPermissions`, and Claude Code saves the rule itself.
- `AskUserQuestion` is answered from a `PreToolUse` hook: `allow`, plus
  `updatedInput` carrying the original `questions` and an `answers` map.
- `Notification` arrives with types `permission_prompt`, `idle_prompt`,
  `agent_needs_input` and `agent_completed`, among others.
- A hook that **prints nothing and exits 0 changes nothing**: Claude shows its
  own prompt. That is the fail-safe.
- Hooks can ship inside a Claude Code **plugin** (`hooks/hooks.json`, plus an
  MCP server), so no hand-edit of `settings.json` is needed.
- Plan usage reaches the status line for Pro/Max users as `rate_limits.five_hour` /
  `rate_limits.seven_day` (`used_percentage`, `resets_at`).

**Coucou's relay is the pattern to copy.** Copy the design only: the code is
MIT, but the name, the character, the icons and the sounds are rights reserved.
Its relay works like this:

- one JSON line over a user-only Unix socket in `$XDG_RUNTIME_DIR`, with a
  `SO_PEERCRED` uid check;
- a 300 ms connect budget;
- the island must confirm the card is on screen within 800 ms, otherwise the
  relay declines to decide;
- app timeout < relay timeout < hook timeout (108 s < 110 s < 120 s);
- **never an allow without a click.**

Its Linux port collapses "Always" into a plain allow; we do it properly through
`permission_suggestions`.

**Subscriptions, honestly** (each line re-verified at every release; the
policies move):

| path | verdict |
|---|---|
| your own API key (Anthropic, OpenAI, Gemini AI Studio, OpenRouter) | allowed |
| local models (Ollama, LM Studio; OpenAI-compatible `/v1`) | allowed |
| ChatGPT plan via OpenAI's "Sign in with ChatGPT" for open-source local apps (preview, ~2026-09-29) | allowed (preview; verify before building) |
| ChatGPT plan via the user's own `codex` (app-server / `codex-acp`) | allowed |
| Claude plan by driving the user's own **unmodified** Claude Code (`claude-agent-acp`, login in Claude's own flow) | **gray**: tolerated, Help Center says it works; the legal page forbids routing plan credentials for users |
| Claude plan by doing Claude.ai OAuth ourselves, or reading `~/.claude/.credentials.json` | **not allowed** |
| Google AI Pro/Ultra: Gemini CLI stopped serving consumer accounts on 2026-06-18; `antigravity-acp` is unsettled; reusing its OAuth gets accounts banned | **gray → not by default** |

**Agent Client Protocol (ACP)** v1 is stable. The Rust crate is
`agent-client-protocol`; majors move fast, so pin it. The registry lists Claude
(`claude-acp`), Codex (`codex-acp`), Gemini CLI (`--acp`), Antigravity, OpenCode
(`opencode acp`), goose and others.

Each agent does **its own login** and asks permission with
`session/request_permission` (`allow_once`, `allow_always`, `reject_once`,
`reject_always`). That is the clean way to "use your subscription" without
ewe ever touching a token.

**ewe today:**

- **Nothing can take over notification banners.**
  - The `NotificationServer` is internal (`docs/PLUGINS.md` "internal");
    `Notifications.qml:80-98`.
  - There is no `notifications` IPC target.
  - History dies with every shell restart, and `ewe-plugin enable` restarts
    the shell.
  - DND lives in memory only (`Globals.qml:51`).
- **There is a place for the island.** The bar's centre is empty by design
  (the clock lives in the Quick settings pill; `CLAUDE.md`), and
  `InvertedCorner.qml` (a fillet "so the panel looks like it flares out of the
  topbar") exists unused.
- **ewe-browser** (Electron 44) toasts a finished download inside its own
  window only (`downloads.ts` → `windows.focused()?.toast`). Its AI button is a
  disabled placeholder.
- **`ewe-pass`** is a fill picker (1Password, Bitwarden, pass), not a vault.
- **No tool reports storage**: sysmon reads CPU and memory only.

## The shape

```
agents in any terminal                 any app                    ewe services
(claude, opencode, codex, gemini…)     notify-send / D-Bus        updates.json · ewe-conf sync-status
   │ hooks                                 │                       ewe-cloud status · ewe.mail · ewe-caldav
   ▼                                       ▼                       statvfs · ewe-browser downloads.json
ewe-companion hook ──┐        shell NotificationServer                  │ (polled, event-driven)
 (relay, Rust, ms)   │                     │ Plugin API 4               │
                     │                     ▼                            │
                     │          ewe.companion plugin (QML) ◄────────────┼──── the ISLAND: presence, peeks,
                     │           island · cards · chat · presenter      │     cards, chat, notification banners
                     │                     │ JSON lines                 │
                     ▼                     ▼                            ▼
             $XDG_RUNTIME_DIR/ewe-companion.sock ──► ewe-companiond (Rust daemon, user unit)
                                                     event bus · attention engine · watchers
                                                     providers (direct lane + ACP agent lane)
                                                     tool registry (tiers, undo) · SQLite store
                                                          │
                     ewe-companion mcp ◄──────────────────┤  ewe tools for agent sessions
                     ewe-companion (Tauri window, later) ◄┘  chat history, sessions, providers, privacy
```

- **The island** is a first-party plugin, because layer-shell surfaces stay in
  the shell (rule 3) and anything beyond the shell core is a plugin (D1).
- **The brain** is a daemon, because state that outlives the shell lives
  outside it (rule 11). A shell restart must not drop a pending permission
  request or a half-streamed answer. The daemon starts on demand from the
  plugin (the ewe-castd pattern).
- **The window** is a Tauri app (Process Split). It is the place for things too
  big for the island: history, sessions and diffs, provider logins, privacy and
  memory.

## Rules this RFC adds (C1–C8)

These are proposed, and become Rules of the House when the companion ships.

1. **C1 — It never decides for you.** No allow without a click. Silence means
   the agent's own prompt.
2. **C2 — It fails back to the old way.** If the daemon or the shell is down,
   the screen is locked, or the time runs out, the agent asks in its terminal
   and notifications show as stock banners (a core watchdog).
3. **C3 — Secrets never reach a model.** No tool returns a secret. The future
   password manager gives it counts and events, never values. Redaction runs
   before anything leaves the machine. A canary test guards this.
4. **C4 — Untrusted text cannot act.** Notifications, web pages, file names and
   agent output are data. A turn that carries them cannot auto-run any tool.
5. **C5 — It works with no AI.** Approvals, the presenter, digests and the
   storage, update and sync watchers are deterministic. AI adds chat and
   actions on request.
6. **C6 — Attention is a budget.** The island's levels are log, glance, peek
   and card; there is no modal and no focus steal. There is a cap on
   unrequested nudges and a "not about this again" on each one. It stays quiet
   while you are fullscreen or casting, during an event in your calendar, and
   in DND.
7. **C7 — It holds no subscription credential.** Plan logins happen in the
   provider's own flow (the agent lane). Keys and tokens the user gives it live
   in the keyring only (rule 2).
8. **C8 — It uses ewe's pipelines.** Settings go through `ewe-conf`, sync
   through ewe-sync (rule 6), packages through Komble (rule 10). It never runs
   pacman, never pushes or pulls the file, and never writes `generated/`.

## What changes where

| repo | change |
|---|---|
| **ewe** | Plugin API 4 (superset of 3): `Shell.notifications`, `notificationPosted/Closed`, `claimBanners/releaseBanners/presented` with a watchdog, `invoke/dismiss/clear`, `setDnd`. A new IPC target `notifications` (list, count, dismiss, clear, dnd, toggleDnd, status). The Notification card items not yet built: action buttons, sticky critical, hover pause, DND lets critical through. An `ewe-conf` `_domain` route for `[companion]` (otherwise every `set` regenerates everything and reloads Hyprland). Design-system cards `Island` and `CompanionCard`, plus presence tokens. Vendored `plugins/ewe.companion` with `bundle.json default:false` |
| **ewe-companion** (new) | `ewe-companiond`, `ewe-companion` (CLI, `hook`, `statusline`, `mcp`), the Claude Code plugin (hooks + MCP), the OpenCode plugin, PKGBUILD + user unit; later the Tauri window |
| **ewe-plugin-companion** (new) | island, cards, chat, presenter; API 4 |
| **ewe-browser** | a finished or failed download sends a desktop notification with `category=transfer.complete` / `transfer.error`, actions *Open* / *Show in folder* and `x-ewe-path`. Later: the AI button asks the companion about the page |
| **komble-arch** | a `DISCOVER` entry; later, if wanted, a cache-clean verb so the companion never needs its own polkit path |
| **ewe-repo** | the publish workflow pulls ewe-companion's release asset |
| **vault / website** | RFC-007 note, component + plugin notes, IPC and Storage sheets, facts; `/docs/cli/ewe-companion` |

## Phases

| # | what | gate |
|---|---|---|
| P0 | owner decisions; HTML mockup `design-mockups/companion.html` (v3 tokens); Island + CompanionCard design cards | the owner signs off the look |
| P1 | repos, Rust workspace, daemon + socket + SQLite, CLI `status`/`say`, user unit; plugin island idle + peek | `ewe-companion say hi` peeks in the nested-Hyprland smoke; a shell restart keeps daemon state |
| P2 | **Claude Code**: relay, Claude Code plugin install, sessions and ticker, permission card (Allow · Deny · Always), question card, finished and idle peeks, jump to terminal, plan-usage pill | approve a real Claude Code tool call from the island; kill the daemon mid-request and Claude falls back to its own prompt |
| P3 | **notifications**: ewe Plugin API 4 + `notifications` IPC, presenter, history in the daemon, old-notification reminder, digest on return, attention engine v1; browser download contract | break the plugin and a critical notification still shows as a stock banner; a download shows *Open* / *Show in folder* |
| P4 | **the brain**: chat in the island; direct-lane providers (Anthropic, OpenAI, OpenAI-compatible: Gemini, OpenRouter, Ollama, LM Studio); keys via stdin into the keyring; tool tiers T0–T2 with confirm + undo; redaction; usage readout | "set the accent to teal": confirm, apply, undo; an Ollama-only machine works offline; the canary never reaches the mock provider |
| P5 | **watchers + MCP**: storage, updates, sync, mail, calendar; `ewe-companion mcp` (`ewe_ask_user`, `ewe_notify`, status, T1/T2 tools) | a Claude Code session asks you through the island and gets the answer |
| P6 | **agent lane + window**: ACP client (claude-acp, codex-acp, gemini, opencode), Sign in with ChatGPT if verified, the Tauri window; OpenCode, Codex and Gemini hooks | chat on your ChatGPT plan with no token ever read by ewe |
| P7 | **ship**: PKGBUILD, ewe-repo, Komble, bundle.json, website, vault; QEMU e2e; `ewe-release` | fresh ISO → Komble → Companion → approve a Claude prompt |
| P8 | **password manager** (when it exists): metadata contract, health nudges, onboarding | the canary secret in the vault appears in no log, prompt or request |

## Owner decisions (answered 2026-10-14: every proposal accepted)

1. **Face:** eyes only. Two dots that blink and glance toward an event,
   within the motion tokens; reduce-motion holds them still.
2. **Name:** "Companion"; renamed **"Shaun"** by the owner on 2026-10-17
   (the user-facing name only: every id stays `companion`, rule 4).
3. **Notifications:** takeover through Plugin API 4 with the core watchdog
   (P3). The `replace_banners` setting stays off by default.
4. **Subscription lanes:** API keys, local models and ChatGPT (Codex / Sign
   in with ChatGPT) ship on. The Claude Code and Antigravity lanes ship off,
   as opt-in "uses your own login" toggles.
5. **Language:** Rust for the daemon, CLI and relay.
6. **Autonomy:** T1 desktop actions run on their own with an Undo peek;
   T2 and T3 always ask.
7. **kitty remote control:** yes. ewe's kitty config gets
   `allow_remote_control socket-only` and `listen_on unix:@kitty-{kitty_pid}`
   (P2), with the same-uid note in Security Posture.
8. **Claude Code install:** a Claude Code plugin from a local marketplace;
   the `settings.json` merge stays as the fallback.
9. **Package-cache cleaning:** through a Komble verb (P5).
