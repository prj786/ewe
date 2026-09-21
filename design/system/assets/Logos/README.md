# Logos

The ewe mark is a line-art sheep inside a circle ("ewe", as in the sheep). Use these files as they are: never redraw, recolor, stretch or add effects to them.

- `ewe-logo-dark.png` (871 × 854): white line art for dark backgrounds. This is the one to use across the desktop.
- `ewe-logo-light.png` (871 × 854): dark line art for light backgrounds, such as documents and the repository page in light mode.
- `ewe-logo-256.png` (256 × 251): the small white mark on the Welcome screen and the browser's new-tab page.
- `ewe-logo-consent-120.png` (120 × 120): the square 120px mark for sign-in consent screens (the OAuth app logo).
- `ewe-mark.svg` and `ewe-mark-bold.svg`: the same line-art logo as a single-ink vector (traced from `ewe-logo-dark.png`, `fill="currentColor"`). One mark everywhere: the regular weight from 64px up (heroes, the fetch logo), the bold cut below that (the dock's launcher button, Quick settings, every app's side navigation), because the hairlines of the regular weight vanish under 40px. They replaced the cartoon sheep head (`sheep.svg`) on 2026-09-21. Inside the shell the copy in `dotfiles/quickshell/assets/ewe-mark.svg` is white and tinted with a `MultiEffect` (`text-primary`, or `accent`), so it follows the active scheme; the apps inline the SVG and let it inherit the text colour.

Keep clear space around the mark of at least a quarter of its width, and don't show the bold cut smaller than 20px or the regular weight smaller than 64px.
