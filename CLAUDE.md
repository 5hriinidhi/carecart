# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This is a **Claude Design handoff bundle** (from claude.ai/design), not a running application. It
contains HTML/CSS/JS design prototypes of **CareCart**, a mobile app concept. There is no build
system, package manager, test suite, or git repository here yet — those get created when
implementation starts.

The job described by `gradient-ascend-mobile-app/README.md`: recreate the prototypes
**pixel-perfectly** in whatever production stack fits the target (React Native, Flutter, native, a
web app — **decide this with the user before implementing**). Match the visual output; do not port
the prototype's internal structure.

### Files

- `gradient-ascend-mobile-app/project/CareCart App.dc.html` — the primary design. Read it in full.
- `gradient-ascend-mobile-app/project/android-frame.jsx` — `AndroidDevice` device-frame component
  the design imports. A copied "omelette starter" (`@ds-adherence-ignore`); treat as read-only —
  it is overwritten if the starter is re-copied.
- `gradient-ascend-mobile-app/project/support.js` — **generated** dc-runtime (a ~2k-line mini-React
  that renders the `.dc.html` format). Never edit; it is rebuilt from a separate `dc-runtime`
  source tree with `bun run build`.
- `gradient-ascend-mobile-app/project/uploads/` — the original proposal PDFs and pasted images.
- `gradient-ascend-mobile-app/project/.thumbnail` — preview asset, ignore.

Do not open these files in a browser or screenshot them unless the user asks — all dimensions,
colors, and layout rules are in the source.

## Reading the `.dc.html` format

The file has two parts: an `<x-dc>` template and a `<script type="text/x-dc" data-dc-script>`
holding a `class Component extends DCLogic`.

- **Logic**: `Component` has a `state` object, mutation methods (`setState`, timer helpers), and a
  single `renderVals()` that returns one **flat object** — every key in it is what the template
  binds to. Most values are precomputed **inline style objects**; styling lives in `renderVals()`,
  not the template.
- **Template tags**: `{{ path }}` interpolation (supports `.`, `[]`, `===`, `!`, literals — no
  arbitrary JS); `<sc-if value="{{ x }}">`; `<sc-for list="{{ xs }}" as="item">` exposing
  `{{ item.field }}` and `$index`; `style="{{ styleObj }}"`; `style-hover="…"` for pseudo-classes.
- `<x-import component-from-global-scope="AndroidDevice" from="./android-frame.jsx"
  hint-size="428px,908px">` mounts the device frame; its children are the screen content.
- `data-props` on the script declares editor-tunable props: `accentColor`, `warningTone`
  ("Calm and reassuring" vs "Direct and blunt"), `showDemoPicker`.

## Design content and architecture

The file holds two "turns", each with lettered options (anchors `#1a`, `#2a`, …):

- **`1a` — the main tappable prototype.** 9 screens driven by `state.screen` / `state.tab`:
  `home, scan, analyzing, result, trends, history, meds, search, nudge`, plus a profile bottom
  sheet and a persistent bottom nav with a center scan FAB.
- **`2a` — sign-in & onboarding.** A second, **independent** state machine in the same
  `Component`, all keys prefixed `o*` (`oScreen`: `login → otp → steps → building → done`;
  `oStep` walks 6 profile steps: gender, activity, body, diet, allergies, meds). Rendered as its
  own `AndroidDevice`. `2a` ends where `1a` begins.
- **`1b`–`1e`** — static layout explorations (verdict-screen and dashboard variants); no logic.

Key patterns:

- **Two state machines, one class.** Main app keys are unprefixed; onboarding keys are `o*`. Keep
  them separate when you split this into real screens.
- **Fake async via `setTimeout`** (`timers`, `otpTimers`): scan "analyzing" step progression, OTP
  auto-fill, profile "building" progression. Real implementations replace these with actual calls.
- **All data is hardcoded top-level consts**: `PRODUCTS`, `HISTORY`, `MEDS`, `TREND`,
  `TREND_LABELS`. These define the demo fixtures.
- **Severity model** (`SEV` + `chipFor`): score ≥ 70 → `safe`, ≥ 45 → `caution`, else `avoid`;
  each tone has a color (`#4A5A33` / `#B8860B` / `#B44F35`) and a tint.

### CareCart product concept

Scan a food label → get a verdict scored 0–100 and personalized: cross-checked against the user's
medications, conditions, allergies, and profile-derived per-serving nutrient ceilings (not generic
RDA). Allergens are a hard full-screen stop, not a score deduction. Framing throughout is
on-device / encrypted / user-deletable.

### Visual system

- Fonts (Google Fonts): **Bricolage Grotesque** (headings/display), **DM Sans** (body),
  **DM Mono** (labels, codes, timestamps).
- Palette: warm paper `#F1F0E4` / `#FBFAF2` / `#E7E5D6`, ink `#15150F` / `#20241A`, olive
  `#63753F` / `#3E4A28`, sage `#BCD5A3` / `#DCE8CE`, terracotta accent `#E39B74` / `#D07E52`,
  plus the three severity colors above.
- Device canvas: 428 × 908 (`hint-size`).
