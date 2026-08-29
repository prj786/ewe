# The "ewe" Google OAuth client — strategy and setup

## How it works for USERS (the point)

Nothing. Users click "Sign in with Google" and consent — the OS ships a
project-owned client (`/usr/share/ewe/system/oauth-client.json`, committed
as `system/oauth-client.json` once minted). Nobody opens a cloud console.
A Desktop-app client's secret is non-confidential by Google's own
definition; the refresh token — the actual credential — never leaves the
user's keyring.

## Scope strategy (why Mail is opt-in)

Google tiers scopes, and the tiers decide what an unverified client may do:

| scope | tier | unverified client |
|---|---|---|
| openid/email/profile | basic | fine |
| drive.appdata | non-sensitive | fine |
| calendar.readonly | sensitive | works, shows the "unverified" warning |
| gmail.readonly | **restricted** | **blocked** except listed test users; full verification = CASA security audit |

So the shipped client signs everyone in with **base scopes** (identity,
calendar, the one-file sync). **Mail is an extra, explicit consent** —
`ewe-auth login --with-mail` — available to accounts on the client's
test-user list (up to 100) and to anyone using a personal client. The shell
already degrades cleanly when a token lacks the mail scope (the Mail card
shows its re-consent state). If ewe ever outgrows 100 mail users, CASA
verification is the gate to budget for — until then this is the honest
maximum Google allows.

Personal clients (`~/.config/ewe/oauth-client.json`) still override the
shipped one and get the full scope set by default — the owner's setup keeps
working unchanged.

## Minting the project client (owner, once)

1. console.cloud.google.com → New project → **ewe**.
2. OAuth consent screen: External · name **ewe** · scopes: the base set +
   gmail.readonly · publish **In production**. Add your own account (and
   future testers) under **Test users** — that's what unlocks Mail for you.
3. Enable APIs: Calendar, Drive, Gmail.
4. Credentials → OAuth client ID → **Desktop app** → "ewe desktop" →
   Download JSON.
5. Commit it: `cp ~/Downloads/client_secret*.json system/oauth-client.json`
   in the ewe repo (PKGBUILD ships it into /usr/share/ewe/system/). Done —
   every install signs in as "ewe" from the next release.
