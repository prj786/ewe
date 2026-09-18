# Screensaver

The screensaver shows a quiet clock or a blank screen when the computer is idle, and dims the screen before locking.

## Anatomy
- Always Ewe Dark: `black` background.
- Clock style: the time in `font-size-6xl` (64px) weight 300 and the date in 18px `text-secondary`, centered.
- Blank style: nothing.

## Behavior
- Any key, click or (after a short moment) pointer movement dismisses it.
- Before locking, the screen dims to 55% black over 1.5 seconds; any input cancels the dim.
- Idle is paused while media plays, a window is fullscreen or the microphone is in use.

## Where it lives
`dotfiles/quickshell/Screensaver.qml` (IPC `saver`).

## What a build provides
`style` (clock, blank) · `dim` · `onDismiss`.
