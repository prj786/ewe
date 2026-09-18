# Button group

A button group joins related buttons into one control. A split button pairs a main action with a menu of alternatives.

## Variants
| Variant | Use |
| --- | --- |
| Toggle group | Mutually exclusive options that look like buttons; the selected one gets `accent-subtle`, `accent-text` text and border |
| Icon group | Formatting or alignment options |
| Action group | Related actions such as zoom out, reset and zoom in |
| Split button | A main action with a `chevron-down` that opens a Menu of variants |

## Anatomy
- Buttons touch; only the outer corners keep the `primary` radius. Secondary buttons share their 1px borders.
- In a primary split button, a 1px `on-accent` line at 30% separates the two parts.

## Do and don't
- Do keep the main action of a split button the most common one.
- Don't join more than five buttons.
- Prefer a Segmented control when the options change a setting.

## Accessibility
- A group labeled by its purpose. The split button's arrow is a separate button named “More … options”.

## What a build provides
`buttons` · `variant` · `value` · `onChange`; split button: `action` · `menu`.
