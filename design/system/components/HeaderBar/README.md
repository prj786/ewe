# Header bar

A header bar sits at the top of a window or page with its title, a way back and the main actions.

## Variants
| Variant | Use |
| --- | --- |
| App header | 48px tall (`control-2xl`), 16px side padding, a 1px `border-subtle` line below. Title 15px weight 600 with a `caption` subtitle. |
| Page title | Inside a pane: title 22px (`font-size-2xl`), description 13px in `text-secondary`, actions aligned to the bottom. |

## Anatomy
1. Back button (optional): a ghost Icon button with `arrow-left`.
2. Title and subtitle, truncated with an ellipsis.
3. Actions: Icon buttons, small search fields, or up to two Buttons, 4px apart.

## Do and don't
- Do keep the primary action of the page in the header, on the right.
- Don't put navigation tabs and a search field in the same header; move tabs below.

## Accessibility
- The title is the page's main heading. Hyprland has no title bars, so the header is also what the window switcher shows.

## What a build provides
`title` · `subtitle` · `variant` (app, page) · `back` · `actions`.
