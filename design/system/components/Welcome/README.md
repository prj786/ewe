# Welcome

Welcome is the first-run card: connect to the internet, install updates, sign in, restore a backup and take a short tour.

## Placement
- A card centered on the screen, `panel-lg` wide, with no scrim, a few seconds after the first login. It never appears on the live installer.
- Opening it again from Settings starts at the first step.

## Anatomy
1. Card: `surface-raised`, 1px `border-subtle`, `rounded` radius, `shadow-float`.
2. Body: 32px padding, 16px gap, centered. A 64px glyph tile (`accent-subtle`, 32px `accent-text` icon) or the sheep mark in `text-primary` on the first step; a 22px weight 600 title; 15px `text-secondary` text; 12px `text-muted` notes.
3. Footer: above a divider, six progress dots (the current one a 16px `accent` pill, done ones `text-secondary`), then a ghost and a primary Button.

## Steps
| Step | Content | Buttons |
| --- | --- | --- |
| Welcome | sheep mark, "Welcome to ewe" | Later · Get started |
| Network | Wi-Fi picker; moves on shortly after coming online | Continue offline · Continue |
| Updates | status, Spinner, the last lines of the log (a `danger` box when it fails) | Skip for now · Install updates / Retry |
| Account | server field, "Waiting for the browser…", links to open or copy the sign-in page | Skip · Sign in |
| Restore | what will be restored, progress | Start fresh · Restore my desktop |
| Tour | four rows: Super, the dock, Quick settings, Komble; optional cards for apps to restore and backup | Finish |

Steps that can't apply (offline, already signed in, nothing to restore) are skipped.

## Behavior
- Enter goes to the next step when it can; Esc finishes, except while updates are installing.

## Accessibility
- A dialog; each step's title is its name; the dots are announced as “Step 2 of 6”.

## Where it lives
`dotfiles/quickshell/Welcome.qml` (IPC `welcome`).

## What a build provides
`step` · `online` · `updates` (state, log) · `account` · `backup` · `onNext` · `onBack` · `onFinish`.
