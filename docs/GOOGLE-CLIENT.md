# Minting the "ewe" Google OAuth client

One-time, in the Google Cloud console (the broker takes the result as a
drop-in file — no code changes):

1. https://console.cloud.google.com → New project → name it **ewe**.
2. **APIs & Services → OAuth consent screen**: External · app name **ewe** ·
   your support email · add scopes: `openid`, `email`, `profile`,
   `calendar.readonly`, `drive.appdata`, `gmail.readonly` · **Publish** the
   app (In production — the unverified-app warning is a one-click through
   for your own account; gmail.readonly is a restricted scope and this is
   the personal-use path).
3. **APIs & Services → Enabled APIs**: enable *Gmail API*, *Google Calendar
   API*, *Google Drive API*.
4. **Credentials → Create credentials → OAuth client ID → Desktop app**,
   name **ewe desktop** → **Download JSON**.
5. Save the download verbatim as `~/.config/ewe/oauth-client.json`
   (the `{"installed": {...}}` wrapper is fine as-is).
6. `ewe-auth login` — one consent for every ewe app. The broker notices the
   client changed and asks for exactly one re-login; the old client's token
   is cleared automatically.

Check: `ewe-auth status` → `"client": "ewe"`.
