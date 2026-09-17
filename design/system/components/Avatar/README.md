# Avatar

An avatar represents a person, an account or a machine with a photo, initials or an icon.

## Sizes
| Size | Pixels | Use |
| --- | --- | --- |
| xs | 24 | Inline mentions, table rows |
| sm | 28 | List rows |
| md (default) | 32 | Quick settings header |
| lg | 48 | Accounts, power menu |
| xl | 64 | Lock screen |
| 2xl | 96 | User settings, installer |

## Content
- **Photo:** cropped to fill.
- **Initials:** one or two letters, weight 600, `accent-text` on `accent-subtle`.
- **No picture:** a `user` icon in `text-secondary` on `surface-hover`.
- **Services and machines:** the square form with the `primary` radius.

## Status
A dot at the bottom right, a quarter of the avatar's size, with a 2px ring in the surface color: `success` online, `warning` away, `danger` busy, `text-disabled` offline. Always repeat the status in text nearby.

## Group
Overlapping avatars step 8px; each has a 2px ring in the surface color. Show at most three, then a “+N” avatar.

## Accessibility
- The avatar's name is the person's name; decorative avatars next to a visible name are hidden.

## What a build provides
`name` · `image` · `size` · `shape` (circle, square) · `status` · `icon`.
