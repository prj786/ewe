# Insomnia — an ewe plugin

`ewe.insomnia` — first-party, ships inside the ewe payload, not installed
until you ask for it.

Keeps the screen awake and stops sleep until you turn it off. While it is
on, the shell holds a Wayland idle inhibitor, so the idle timers never fire:
no auto-lock, no screen blank, no auto-suspend. The lid and a manual lock
still work. Off releases the inhibitor and normal idle behaviour resumes at
once.

- A tile in Quick settings (eye open while on, eye-off while off).
- An eye in the bar's Quick settings pill, only while on.

Install: Komble → Plugins, or

    ewe-plugin install ewe.insomnia

Settings (Komble → Plugins → Insomnia → Options, or `ewe-plugin set
ewe.insomnia auto_off 30`):
`auto_off` — turn off by itself after this many minutes; `0` (the default)
means never. The tile's status counts down ("On · off in 25 min") and a
toast says when it happened.

IPC: `qs ipc call ewe.insomnia toggle | on | off | status` — `status`
returns JSON (`on`, `autoOff`, `minutesLeft`, `until`).

Needs nothing beyond ewe. The inhibitor surface keeps the layer namespace
`quickshell:caffeine` the shell used before 0.25, so existing layer rules
keep applying.
