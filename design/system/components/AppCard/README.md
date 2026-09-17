# App card

App cards present apps in Komble: as grid cards, a featured banner and list rows.

## Anatomy (grid card)
1. Card: 208px wide, 12px padding, `surface-raised`, 1px `border-subtle`, `rounded` radius.
2. Top: the 48px app icon, the name (15px weight 600) and the developer (`caption`).
3. Summary: two lines of 13px `text-secondary`.
4. Footer: the source Badge (repository name, AUR, AppImage), the size or version, and one small button.

## Footer states
| App state | Footer |
| --- | --- |
| Not installed | primary “Install” |
| Installed | secondary “Open” |
| Installing | a Progress bar with “Installing… 48%” and a cancel button |
| Update available | `warning` source badge, version, secondary “Update” |

## Featured banner
- `gradient-ewellow` background with `on-accent` text, a 64px app icon, a kicker in `overline`, a 22px title and a one-line reason. The button inverts: `on-accent` fill with `accent` text. The sheep mark sits at 8% in the corner.
- One banner per page at most.

## Sources
- Repository names use a neutral Badge, AUR uses `warning` (built from source), AppImage uses `info`.

## Accessibility
- Each card is a link to the app's page, named by the app; its button is a separate control (“Install GIMP”).

## What a build provides
`app` (name, developer, icon, summary, source, size, version) · `state` · `progress` · `variant` (card, row, featured) · `onOpen` · `onAction`.
