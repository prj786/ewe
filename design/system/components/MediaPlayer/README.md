# Media player

The media player controls whatever is playing, from any app that supports MPRIS.

## Variants
| Variant | Use |
| --- | --- |
| Full | The media popup: 64px art, source, title, artist, a seek slider with times, and five controls |
| Compact | Inside quick settings and notifications: 40px art, title, artist, previous, play and next |
| Nothing playing | Compact, with a `music` icon and a one-line hint |

## Anatomy
- Art: the album cover with the `primary` radius, or `gradient-ewellow` with a `disc-3` icon when there is none.
- Source line: the app icon, name and position in the queue, in `caption` `text-muted`.
- Title 15px weight 600, artist 13px `text-secondary`, both truncated.
- Times in Geist Mono `caption`, tabular.
- Controls: shuffle and repeat (ghost, selected when on), previous and next (ghost), play/pause (primary, round, 40px).

## Behavior
- With several players, arrows switch between them; the most recently active one shows first.
- The seek slider is hidden for streams without a length.

## Accessibility
- Controls are named (“Pause Ruins of Light”); the seek slider reports time, not percent.

## What a build provides
`player` (app, title, artist, album, art, position, length, playing, shuffle, repeat) · `variant` · `onCommand`.
