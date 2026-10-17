# ewe.companion

**Shaun**, the notch under ewe's top bar: the shell half of
[ewe-companion](https://github.com/prj786/ewe-companion) (RFC-007). A tab of
the bar's own glass hangs from the bar's centre while something runs (an
agent at work, a card, a line to say, a question, game mode), and is gone
otherwise; **Super+A** brings it out. It is one size whatever it says:

- **The indicator:** a state dot plus a word (*Needs you*, *Working*,
  *Stopped*, *Game mode*), how many cards wait, what the agent is doing
  (*Claude · Edit Bar.qml*), and your Claude plan's 5-hour and weekly use.
- **Cards:** when Claude Code wants to run something or asks a question, the
  notch grows to show the card. **Allow** · **Deny** · **Always for …** ·
  **Answer in terminal**.
- **Home:** click the notch, or press **Super+A**. It shows the cards, then
  only what is live now:
  - the agents and their last steps (click one to jump to its terminal);
  - what needs a look (a disk past 85 %, waiting updates, a low battery);
  - what is playing;
  - one-click actions (Do not disturb, game mode, screenshot, Settings,
    Komble, lock);
  - a chat line for questions and commands. It knows ewe (the daemon's
    knowledge pack), and an answer about a place comes with a button that
    opens it. It opens apps the way the launcher does ("open nemo", "open
    kitty in documents"), and it shows a shell command it proposes exactly as
    it will run, with **Run** and **In terminal**: nothing runs without that
    click.
  - what a command found, as a list under its answer: Safe's logins ("copy
    my GitHub password" when several fit: a click copies that one), files
    and folders ("find my resume": **Open**, and small buttons for **Show in
    folder**, **Copy path**, **Open terminal here**), ewe browser's history
    and tabs (**Open**, **Go to**). A locked Safe gets an **Unlock Safe**
    button that opens Safe's own window for the master password.

| kind | file | what |
|---|---|---|
| service | `Service.qml` | the daemon's socket (reconnects, starts the daemon on demand), `env`, `settings`, `do` (what only the shell can do: also ewe browser's command line and Safe's unlock prompt), the blur rule, IPC `ewe.companion` |
| overlay | `Drop.qml`, `Indicator.qml`, `cards/`, `sections/` | the notch on each screen and everything in it |
| — | `CompanionState.qml` | the plugin's singleton: what they share |

IPC (`qs ipc call ewe.companion …`): `toggle` · `open` · `hide` · `status` ·
`ask <text>`.

**Settings** (Komble → Plugins → Shaun → Options):

| setting | default | what |
|---|---|---|
| *Who answers questions* | none | `claude-code` · `codex` · `opencode` (your own login in that app), `anthropic` · `openai` · `gemini` · `openrouter` (an API key), `ollama` · `lmstudio` (on this computer), `custom` (any OpenAI-compatible server). Commands work with none |
| *Model* | empty | the provider's quick model (haiku for Claude Code, the first local model for Ollama) |
| *Server address* | empty | for `custom`, or to point another provider elsewhere |
| *Show on* | the primary screen | the screen in use, or every screen |
| *Show Claude plan usage* | on | needs `ewe-companion agents usage claude on` |
| *Keep a line on screen for* | 5 s | how long a peek stays |

**API keys are not a setting.** Plugin settings live in `ewe.conf`, which
syncs to your account, and a key must never travel there (house rule 2).
The notch asks for the key when the provider needs one and puts it in your
keyring.

## Honest limits

- **It decides nothing.** The cards wait for your click. If this plugin
  fails to load or to draw a card, the daemon gets no ack within 800 ms and
  Claude asks in its terminal.
- **It never steals focus.** A card that drops by itself takes no keyboard
  input. The drop takes the keyboard only when you open it by hand, and Esc
  closes it without denying anything.
- **Cards wait silently in Do not disturb and on the lock screen.** The badge
  counts them, and nothing is drawn on the lock screen. When the screen
  locks, waiting agents ask in their terminals.
- **It is still at idle.** No timers, no animation until something
  changes, so an idle notch costs no CPU. The mascot comes later.
- **The window never resizes while it shows something.** Hyprland stretches
  a layer surface's old buffer to its new size for a frame, which blinked.
  So while the notch is out its window keeps one size (the open notch's
  width, the screen's height), and its input mask is the notch alone. With
  Glass on, the blur pass covers that box while the notch is out; it shrinks
  to 1 px once the notch has gone in.
- **A click outside closes the home panel** through a Hyprland focus grab.
- **The open notch stops at 60 % of the screen.** Past that, the cards, the
  sections and the conversation (the last 40 messages) scroll, with a thin
  bar in the right margin, while the line you type in stays pinned at the
  bottom. A new answer scrolls itself into view; a new card scrolls to the
  top.
- **It never sees a password.** Safe copies it and clears the clipboard
  itself; the notch shows a login's title and username only, and *Copy
  path* is the one thing it puts on the clipboard itself (`wl-copy`).
- **ewe browser's acts run here** (search, open, play, a tab), as
  `ewe-browser` with arguments, never a shell, so a browser they start
  belongs to your desktop. The notch closes first, as it does for apps.
- **It needs the `ewe-companion` package** (`ewe-companiond`). Without it
  the dot stays dim, and hovering says *Shaun is off*.
- **The notch is the bar's own material.** With Glass on it blurs the
  wallpaper behind it, as the bar does (a Hyprland `xray` blur rule), so a
  window under the notch never shows through it. Without compositor blur
  (`EWE_NO_BLUR`: VMs, NVIDIA; or a bar under 10 % opacity) the window under
  it shows faintly through the glass.
- **The notch covers a strip at the top centre of the window under it**,
  like a phone's notch. A fullscreen window covers the notch.
- **It runs unsandboxed, like every plugin.**

## Develop and test

Working on it (people and agents): [`AGENTS.md`](AGENTS.md) here, and
[`ewe-companion/AGENTS.md`](https://github.com/prj786/ewe-companion/blob/main/AGENTS.md)
for the whole picture. To see a change without installing anything, use the
companion's island harness: a debug daemon and this plugin in ewe's nested
shell, with a virtual mouse.

```sh
cd ../ewe-companion
tests/island.sh up --scale 1.8
tests/island.sh ctl debug card permission     # or question / note
tests/island.sh shot card
tests/island.sh sync                          # after editing the QML here
tests/island.sh down
```

The rest is in `ewe-companion/docs/TESTING.md`.

MIT licence.
