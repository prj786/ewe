# Empty state

An empty state explains why there is nothing to show and what to do next.

## Anatomy
1. Icon: a 48px circle in `surface-hover` with a 24px icon in `text-secondary`.
2. Title: 15px weight 600.
3. Description: 13px in `text-secondary`, at most 250px wide.
4. Actions (optional): one secondary or ghost Button.

## Variants
- **Page:** 32px × 16px padding. **Compact:** a 32px icon and a 13px title, for panels and popups.

## Writing
- Say what happened and what to do: “No apps match “blendr”. Check the spelling, or search the AUR.”
- Good news is also an empty state: “Everything is up to date.”

## Do and don't
- Do keep the layout of the surface around it, so the page doesn't jump when content arrives.
- Don't use illustrations or emoji.

## Accessibility
- The title is announced when a list becomes empty after a search.

## What a build provides
`icon` · `title` · `description` · `action` · `compact`.
