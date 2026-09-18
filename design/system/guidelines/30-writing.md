# Writing

Ewe's words should feel like its design: calm, clear and short. People are in the middle of something; the text should help them finish it, not ask for attention.

## Voice

- **Plain.** Use the words people use: "Wi-Fi", "Restart", "Updates". Never service names, package names or command output in headlines.
- **Calm.** No exclamation marks, no "Oops", no blame. Say what happened and what to do next.
- **Short.** One idea per sentence. Cut "please", "successfully", "in order to", "simply".
- **Direct.** Address the person as "you" only when it helps; name the thing instead ("Wallpaper saved to Pictures", not "You have saved your wallpaper").
- **Honest.** If something will be lost, say what. If something will take long, say roughly how long.

## Capitalization and punctuation

- Sentence case everywhere: titles, buttons, menu items, tabs, settings ("Reduce transparency", not "Reduce Transparency").
- Capitalize names of apps and shell places: Komble, ewe-sync, Places, Overview, Quick settings, Welcome.
- No period after titles, buttons, labels or single-line list items. Descriptions, helper text and sentences end with a period.
- Use an ellipsis (…) on actions that need more input before they run ("Select a region…") and on progress ("Installing…"). Use the single character, not three dots.
- Use curly quotes (“ ” and ’). Georgian text uses „ “.
- Keyboard keys are written with Kbd: Super, Ctrl, Alt, Shift, Enter, Esc, Tab, Space; combinations with "+": Super+Shift+W.

## Buttons and actions

- Start with a verb that says what happens: "Install", "Restart now", "Remove linux-zen", "Allow". Avoid "OK" and "Yes"/"No".
- The primary action repeats the verb of the title: title "Restart to finish updating?" → button "Restart now".
- The way out is "Cancel", or "Later" / "Skip for now" when nothing is being undone.
- Destructive actions name the thing: "Delete 3 files", not "Delete".
- Links read as destinations: "Open Settings", "Open the sign-in page". Never "click here".

## Messages

| Kind | Pattern | Example |
| --- | --- | --- |
| Error | What happened. What to do. | "Couldn't join office: the password was rejected." / "Disk is full. Free up 2.1 GB and try again." |
| Confirmation (toast) | Past tense, name the thing | "Moved **report.pdf** to Trash" · Undo |
| Question (dialog) | The decision, as a question | "Remove linux-zen?" |
| Warning | The consequence first | "3 partitions will be deleted" |
| Empty state | What's missing. What to do. | "No pinned apps yet" / "Search for an app and use its pin to keep it here." |
| Progress | Present participle and ellipsis | "Checking…", "Moving 3 files…" |
| Offline | State and what still works | "Offline" / "Showing events from the last sync." |

- Error codes and technical details go in a details section or the log, never in the headline.
- Don't apologize ("Sorry") and don't thank ("Thanks for waiting").

## Numbers, units and time

- Sizes use decimal units with one decimal when under 10: "2.1 GB", "84 KB", "412 GB". A space between number and unit, a non-breaking one in the interface.
- Percentages have no space: "72%".
- Durations in the largest sensible unit: "45 min", "about 2 minutes", "1 h 20 min".
- Relative times for recent things: "now", "2 min ago", "Yesterday"; then the date.
- Dates and times follow the person's locale. English (US spelling) with the ewe defaults: "Thu 17 Sep" in the bar, "Thursday, 17 September" in headings, "04:18 PM" or "16:18" by the 12/24-hour setting.
- Numbers that change in place (clock, battery, counters) use tabular figures.

## Georgian (ka)

- Georgian text runs about 30% longer than English. Buttons and labels grow; they never truncate. Descriptions wrap.
- Georgian has no capital letters in running text. Never apply uppercase transforms to it: CSS and Qt would turn Mkhedruli into Mtavruli. Overline headers in Georgian keep their letters and use only the letter spacing.
- Geist has no Georgian glyphs; Noto Sans Georgian is the fallback in both font stacks and must be installed. Check that line heights still fit: Georgian letters reach higher and lower than Latin ones.
- Georgian uses 24-hour time and day-month order: "ხუთ, 17 სექ · 16:18".
- The keyboard layout indicator shows "GE" for Georgian and "US" for English.

## Word list

| Use | Don't use |
| --- | --- |
| Quick settings | control center, control centre, action center |
| Overview | activities, expose, mission control |
| workspace | desktop (for a workspace), virtual desktop |
| window | client, surface |
| app | application, program (except in "Application" result tags) |
| sign in, sign out | log in, login (as a verb) |
| Wi-Fi | WiFi, wifi, WLAN |
| Bluetooth | BT |
| update, updates | upgrade, sync (for packages) |
| Trash | recycle bin, bin |
| Places | file panel |
| Komble | the store, package manager (in the interface) |
| scheme | theme (for color schemes) |
| accent color | primary color, brand color (in the interface) |
| pin, unpin | favorite, bookmark |
| keep awake | caffeine, inhibit |
