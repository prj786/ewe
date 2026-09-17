# Install wizard

The install wizard walks people through a multi-step flow, such as installing ewe.

## Anatomy
1. Window: `surface-base`, `rounded` radius.
2. Top: the sheep mark and a horizontal Step indicator.
3. Body: a 28px weight-600 title (`font-size-3xl`), a 15px description, then the step's choices and fields, 16px apart, with 48px side padding.
4. Choices: large selectable cards with a radio, a 40px icon tile, a 15px title and a description. The selected card gets `accent-subtle`, a 2px `accent-text` edge and an `accent` icon tile.
5. Footer: “Step 3 of 5” on the left, then ghost Back and primary Continue as xl buttons.

## Rules
- One decision per step. Continue stays disabled until the step is complete.
- Destructive consequences show as a danger Inline alert on the step where they are chosen, and again on the final summary.
- Back never loses what was entered.

## Accessibility
- Each step is a form named by its title; the step indicator announces progress.

## What a build provides
`steps` · `current` · `title` · `description` · `content` · `canContinue` · `onBack` · `onContinue`.
