# ewe-plugin-slack

Unread Slack direct messages on the [ewe](https://github.com/prj786/ewe)
desktop: a card with the avatar, name, last unread line, time and count of
every unread DM and group DM, newest first. A click on a row opens that
conversation in the Slack app (or the browser, see settings). Channels are
left out on purpose.

| kind | file |
|---|---|
| the model, singleton `SlackInbox` | `SlackInbox.qml` |
| `service`: starts the model, IPC, refetch after suspend | `Service.qml` |
| `desktop-widget`: the card | `Widget.qml` (+ `SlackRow.qml`, `SlackAvatar.qml`) |
| `panel`: the Connect window (token in, keyring) | `Setup.qml` |
| the Slack Web API pass (one JSON line per run) | `slack-unread.py` |

Move it with arrange mode (`Super+Shift+W`), where it can also be made
sticky (above windows) or hidden.

## Setup

Install it (Komble → Add-ons → Slack, or `ewe-plugin install ewe.slack`). On
the first start the **Connect Slack** window opens (later: the cog on the
card, or `qs ipc call ewe.slack connect`):

1. **Create the Slack app** opens Slack's "new app" page with the manifest
   ([`slack-app-manifest.yaml`](slack-app-manifest.yaml): read-only user
   scopes, no bot) already filled in. Pick the workspace, *Create*, then
   *Install to Workspace*. Some workspaces need an admin to approve it.
2. Copy the **User OAuth Token** (`xoxp-…`) from *OAuth & Permissions*, paste
   it into the window, **Connect**.

The token goes from the field to `slack-unread.py --connect` on stdin, is
checked with Slack (`auth.test`) and only then stored in the keyring
(`service ewe-slack account user-token`). It never touches `ewe.conf`, argv or
a file. The same window shows whom you are connected as, and **Disconnect**
clears it from the keyring.

By hand, the same thing:

```sh
secret-tool store --label='Slack (ewe)' service ewe-slack account user-token
python3 slack-unread.py --state-dir /tmp/slack-test | python3 -m json.tool
qs ipc call ewe.slack status
```

## Settings

`ewe-plugin set ewe.slack <key> <value>` (or Komble → Add-ons → Slack):

| key | default | |
|---|---|---|
| `poll_seconds` | `60` | how often to check (doubled on battery, at least 30) |
| `max_rows` | `6` | conversations shown on the card (1–12), the rest as "+N more" |
| `background` | `solid` | `solid`: an opaque card in the theme's base surface; `glass`: ewe's own Glass card |
| `open_with` | `app` | `app` opens `slack://channel?team=…&id=…`; `browser` opens app.slack.com |
| `include_bots` | `false` | also show DMs from bots and Slackbot |

## How "unread" is worked out

A user token has no public unread counter, so for every DM the helper compares
`conversations.info` → `last_read` with the newest message from someone else,
and counts the newer ones (up to 20). Slack allows about 50 of those checks a
minute, so one poll checks at most 40 DMs: unread, new and recently active
(14 days) ones first, then whichever were checked longest ago. With a lot
of DMs the first few polls fill the picture in, and a DM from someone you
have not talked to for weeks can take about 15 minutes to appear. Names and avatars are cached for a day under
`~/.local/state/ewe/plugins/ewe.slack/`.

> Plugins run unsandboxed inside the shell process. This one runs
> `python3 slack-unread.py`, `secret-tool lookup` and `xdg-open`, and talks
> to `slack.com` only.

MIT.
