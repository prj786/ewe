# Key–value list

A key–value list shows labeled details, such as system information or the properties of a network.

## Anatomy
1. Two columns: the label column is as wide as its longest label; the value column takes the rest, with 16px between them.
2. Label: 13px in `text-muted`. Value: 13px in `text-primary`. Technical values (versions, IDs, addresses) use Geist Mono 12px.
3. Rows are 4px from each 1px `border-subtle` divider; the last row has no divider.
4. Value extras (optional): a Badge, or a copy Icon button aligned right.

## Do and don't
- Do offer a copy button for values people paste elsewhere (IDs, addresses).
- Do shorten long IDs in the middle ("4f2a…9c1e") and show the full value in a tooltip.
- Don't use it for editable values; use List rows with controls.

## Accessibility
- Built as a description list, so each value is read with its label.

## What a build provides
`items` (label, value, mono, copyable, badge).
