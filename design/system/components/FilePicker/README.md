# File picker

The file picker is how every app asks for a file: Open, Upload, Save as, Choose a folder. It also covers "Open with", when an app asks which app should open something. Apps reach it through the desktop portal (RFC-011), so it looks the same whichever app asks.

## Placement
- A large panel centered on the focused screen over `scrim`, at most 880px wide (`panel-lg` + `panel-sm` − `space-lg` − `space-s`) and 624px tall (`panel-lg` + `space-xl`), and 80px from the screen edges.
- It sits on the overlay layer, above every window, including fullscreen ones. The app that asked can never cover it.
- Clicking the scrim does nothing, so a half-made choice isn't lost (as in Dialog).

## Anatomy
1. Panel: `surface-raised`, 1px `border-subtle`, `rounded` radius, `shadow-float`, `space-md` padding and `space-md` between sections.
2. Header: the asking app's icon (`icon-xl`), the title in `h3` (the app's own words, such as "Upload file", or "Open a file", "Open files", "Save as", "Save files", "Select a folder"), the app's name in `caption` `text-muted`, and a close Icon button.
3. Places: a column 180px wide (`panel-sm` ÷ 2) of dense List rows:
   - Recent (Open only, when there is history);
   - Home and the folders from `user-dirs.dirs`;
   - "Your account" (the Nextcloud folder and ewe Sync's folders);
   - "Pinned" (the Places plugin's pins and bookmarks);
   - "Drives".

   Group labels use the `overline` style in `text-muted`. The current place is `accent-subtle`. A 1px `border-subtle` rule separates the column from the folder pane.
4. Toolbar, `control-md` tall:
   - Back, Forward and Up as md ghost Icon buttons, at reduced opacity when they can't be used;
   - the Breadcrumb ("Home › Documents");
   - a search field 180px wide;
   - New folder (Save and Select folder only), Show hidden files, and List or Grid.

   Ctrl+L, a click on the last crumb, or typing `/` or `~` turns the breadcrumb into a path field.
5. Column header (list view): Name, Size, Modified in `caption`. Clicking one sorts by it; the active one shows a chevron. Size is hidden when only folders can be picked.
6. Listing, in a `surface-sunken` well with 1px `border-subtle` and `primary` radius:
   - **List:** rows `control-lg` tall. Each has an `icon-md` glyph (folders in `accent-text`, files by type: picture, video, music, archive, code, document), the name in `body` (elided in the middle), and the size and date in `caption` `text-muted`. Recent rows add the folder underneath (`~/Documents`).
   - **Grid:** square cells of 2 × `control-2xl` + `space-md`. A picture shows its thumbnail at `icon-4xl`, decoded small; anything else shows its glyph at `icon-3xl`. Up to two lines of `caption` sit under it.
7. Save row (Save as): "Name" in `body-strong` and a Text field, with the base name selected so typing replaces it and keeps the extension. Save files shows "Saving" and the names instead.
8. Alert line, above the footer: a `warning` icon and the question ("“draft.txt” already exists. Replace it?"), or a `danger` icon and what went wrong.
9. Footer, above a divider:
   - left: the app's file types (a Select, or a caption when there is one) and the app's own options (checkboxes or Selects, such as "Open read-only" or "Encoding");
   - right: Cancel (ghost) and the primary action (the app's label, or "Open", "Open 3 files", "Save", "Save here", "Select folder"). While a replace is being confirmed, the primary becomes a danger "Replace".

## Open with
- Dialog md (`panel-md`, 400px), the same panel and scrim. The title is "Open with", with "Choose an app for “report.pdf”." in `body` `text-secondary`.
- Rows `control-2xl` tall with the app's `icon-xl` icon and name. The last app used comes first and is selected (`accent-subtle` and a check). Six rows show, then the list scrolls.
- The footer has "Find an app in Komble…" (ghost) on the left, and Cancel and Open on the right. With no app, a compact Empty state says "No app opens this yet".

## States
- Row or cell: hover `surface-hover`; selected `accent-subtle`; the keyboard cursor gets a `focus-width` `focus-ring` on its edge. Files that can't be picked (in Select folder) show in `text-disabled`.
- Loading: a Spinner in the well until the folder lists.
- Empty: "This folder is empty". With a file type chosen: "No matching files here", plus "Pick another file type below, or another folder." when there is another type. When searching: "No matches". Recent: "Nothing recent".
- Busy: the primary button shows its spinner while the answer goes back. If the app can't use the answer, the alert line says so and the picker stays open.

## Behavior
- One picker at a time. Requests from other apps wait their turn.
- It opens on the folder the app asked for, else the one this app used last, else Home. It also remembers List or Grid, hidden files and the sort.
- Click to select. In "Open files", Ctrl+click and Shift+click pick several. A double click opens a folder or picks a file.
- Keys:
  - arrows move the cursor (in a grid, Left and Right too);
  - Enter opens a folder or confirms;
  - Backspace or Alt+Up goes up a folder; Alt+Left and Alt+Right go back and forward;
  - Ctrl+L types a path; Ctrl+F searches this folder; Ctrl+H shows hidden files; Ctrl+A selects all (Open files);
  - typing jumps to a name;
  - Esc clears a question, then cancels.
- Tab moves from the listing to the file type, the options and the footer. Space or Enter opens a Select; its list follows the arrows.
- Save as asks before replacing a file. Typing a folder's name in Name, or a path ending in `/`, opens that folder.

## Accessibility
- A modal dialog named by its title and described by the app's name. The listing is a grid of rows that say name, type, size and date. The Selects and checkboxes are reachable with Tab and show `focus-ring`.

## Where it lives
`dotfiles/quickshell/FilePicker.qml` (IPC `filepicker`: open, close, ping, select, cancel) and `dotfiles/quickshell/AppChooser.qml` (IPC `appchooser`: open, update, close, ping, select, cancel). The portal backend is `bin/ewe-portal`: it hands a request the shell can't answer to the GTK dialog. New in RFC-011.

## What a build provides
`kind` (open, folder, save, saves, app) · `title` · `acceptLabel` · `multiple` · `folder` · `currentName` · `filters` · `choices` · `places` · `recent` · `onAccept` (paths or folder, choices, file type) · `onCancel`.
