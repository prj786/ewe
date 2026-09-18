# Lock screen

The lock screen shows the time over the wallpaper and asks for the password or fingerprint.

## Anatomy
1. Background: the wallpaper. The lock screen always uses the Ewe Dark roles, whatever the scheme.
2. Time: the `display-xl` clock (64px, weight 300) and the date in 15px `text-secondary`.
3. Account: a 64px avatar and the name in 15px weight 600.
4. Password: an xl Text field with a `lock` icon and a primary Icon button (`arrow-right`); a Spinner replaces the button while checking.
5. Message line: always reserved (14px) so nothing jumps.
6. Corners: keyboard layout, network and battery on the left; accessibility and power on the right.

## States
| State | Field | Message |
| --- | --- | --- |
| Waiting | focused | “Touch the fingerprint sensor or type your password” |
| Wrong password | `danger` border | `danger`, with a `circle-alert` icon |
| Caps Lock on | focused | `warning`, with an `arrow-big-up-dash` icon |
| Unlocking | Spinner in place of the button | “Unlocking…” |

## Behavior
- Any key focuses the field. After three wrong attempts, the field waits 30 seconds and counts down in the message line.
- The clock uses tabular numbers so it doesn't shift.

## Accessibility
- The password field is focused on wake; the message line is announced right away.

## What a build provides
`user` · `time` · `wallpaper` · `state` · `message` · `fingerprint` · `layout` · `onSubmit`.
