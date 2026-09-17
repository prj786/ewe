# Combobox

A combobox is a text field that suggests matching values as people type, such as time zones or apps to pin.

## When to use
- Use it when the list is long (dozens of options or more) and people know what they are looking for.
- Use a Select for short lists, and a Search field when typing is only a filter.

## Anatomy
1. Field: the Text field.
2. Suggestions: a Menu `space-xs` below the field, as wide as the field. The typed part of each suggestion is shown in `accent-text` weight 600.
3. No results: a single line in `text-muted`, centered.
4. Multiple values: chosen values become small removable Tags inside the field, which grows to wrap them.

## Behavior
- Suggestions appear after the first character. Up and Down move, Enter picks, Esc closes the list, and Backspace in an empty field removes the last tag.
- Typing a value that doesn't exist is allowed only when the field accepts free text.

## Accessibility
- A combobox with a listbox popup; the highlighted option is announced as people move.

## What a build provides
`label` · `value` / `values` · `options` · `multiple` · `allowCustom` · `placeholder` · `helper` · `error` · `onChange`.
