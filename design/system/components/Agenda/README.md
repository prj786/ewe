# Agenda

The agenda shows the month and upcoming events inside Quick settings, and reminds people before events start.

## Anatomy
1. Calendar: the month grid (see Calendar); today in `accent`, days with events marked with a dot.
2. Divider, then events grouped by day ("Today", "Tomorrow", then the date) under overline headers.
3. Event row: time in Geist Mono (or "All day"), a 2px bar in the calendar's color, the title and a meta line (time left or duration, place). The event happening now gets `accent-subtle`.

## States
- Offline: a warning Inline alert, "Offline" / "Showing events from the last sync."
- Nothing coming up: Empty state, "No upcoming events" / "Your week is clear."
- No account: Empty state, "No calendar connected" / "Sign in to Nextcloud or Google to see events here." with "Open Settings".

## Behavior
- Sources in order: Nextcloud, Google, then local calendars.
- Reminders arrive as Notifications from "Calendar", once per event.
- While an event starts within the hour or is running, the bar shows a `calendar` indicator.

## Accessibility
- Events are a list; each says its time, title and place.

## Where it lives
`dotfiles/quickshell/Agenda.qml` (data) and the calendar section of `QuickSettings.qml`.

## What a build provides
`events` · `state` (online, offline, signed out) · `onOpenEvent` · `onSignIn`.
