# Vendored fonts

The prototype's three typefaces, committed to the repo so the app renders
correctly on first run **with no network** — nothing is fetched from Google
Fonts (or anywhere) at runtime.

| Family (pubspec) | File(s) | Upstream | License |
|---|---|---|---|
| `Bricolage` | `BricolageGrotesque-VariableFont.ttf` | [Bricolage Grotesque](https://github.com/ateliertriay/bricolage) | OFL 1.1 (`OFL-Bricolage.txt`) |
| `DMSans` | `DMSans-VariableFont.ttf` | [DM Sans](https://github.com/googlefonts/dm-fonts) | OFL 1.1 (`OFL-DMSans.txt`) |
| `DMMono` | `DMMono-Regular.ttf` (400), `DMMono-Medium.ttf` (500) | [DM Mono](https://github.com/googlefonts/dm-mono) | OFL 1.1 (`OFL-DMMono.txt`) |

Bricolage Grotesque and DM Sans are variable fonts — the `wght` axis covers
every weight the design uses (400/500/700/800), so a single asset is declared
per family. DM Mono has no variable build, so the two static weights we use are
declared explicitly.

The `OFL-*.txt` files are kept here for attribution but are **not** listed under
`flutter > assets`, so they are not bundled into the app binary.

Family names and the `kCcFontFallback` chain are defined in
`lib/src/core/theme.dart` / `lib/src/core/text.dart`. To refresh the files, pull
the current `.ttf`s from `github.com/google/fonts/tree/main/ofl/<family>` and
overwrite in place — no other change needed.
