# Us 1.5 presentation audit

Framework: Flutter 3.47.7 / Dart, Riverpod, go_router, Material 3. Android package remains com.jerrish18.us. No backend, business-model, persistence or destination changes.

## Screen and surface inventory

| Surface | Existing controls retained | Visual treatment |
|---|---|---|
| Startup failure, session loading/retry | Retry, same session guard | Mesh backdrop, expressive status, skeleton |
| Sign in and create account | Email, password, Google, confirmation resend | Split hero, stacked form card, dark pill actions |
| Pair/create space | Name, together-since, invite code, join, sign out | Two colored chapters, invite capsule |
| App lock | Device security, PIN, busy | Flower lock medallion, frosted panel |
| Home | Days, milestones, invite, Miss Me, notes, moods, clock, status, location, date/chat links, tap history | Oversized greeting, yellow hero/ring, mixed bento, pink note, horizontal mood/history |
| Main shell | Same five destinations, sync status, active location Stop | Glass header/avatar/find/reminders, floating morphing dock |
| Chat | Search, stars, pins, polls, share inbox, offline queue, drafts, emoji, reply, edit, file/photo/voice, receipts, presence, typing | Blue/lavender bubbles, glass composer, expressive status/header |
| Message action sheet | Reactions, reply, edit, star, pin, forward, share, delete for me/both | Glass sheet, rounded action rows |
| Voice preview/player | Send/discard, play/pause, seek, speed | Capsule controls, tinted player |
| Photo viewers | Zoom, back | Fullscreen mesh, shared photo Hero |
| Poll editor/results sheet | Same options, votes and results | Glass editor, colored rounded results |
| Calendar | Month/day selection, dates, invitations/responses, anniversary countdowns | Coral hero, rounded month panel and date cards |
| Date editor | Title, date/time, place, notes, invite | Glass composer sheet |
| Anniversary repeat chooser | One-time/yearly | Glass choice sheet |
| Memories timeline | Filters, collection management link, heart, move/delete, viewer | Pink/coral editorial photo cards, pill filters |
| Memory composer | Preview, caption, memory date, existing/new/no collection, save/retry/cancel | Collage-like preview, glass fields and collection rows |
| Memory move / delete | Same selection and confirmation semantics | Glass sheets |
| More/settings | Every existing preference and action | Six-color feature tiles, grouped settings cards |
| Time-zone selector / quiet-hour pickers | Search/select, start/end/clear | Glass selection / themed native picker |
| Space deletion confirmation/export | Same warning, backup, unlink behavior | Destructive glass sheet, clear error/busy state |
| Lists | Bucket/to-do/grocery, add/edit/remove/check | Green progress hero, rich checklist cards |
| Journal | Private/shared, write/edit/remove | Lavender editorial cards and privacy chips |
| Letters | Compose, open-when, optional unlock time, reader/sealed state, delete | Pink envelopes, frosted editor/reader |
| Expenses | INR totals, equal split, add/remove | Green balance hero, receipt cards |
| Collections | Create, count, existing memory workflow | Coral folder cards |
| Live location | Timed consent/start/stop, freshness/accuracy, opt-in map, external map, attribution | Blue location hero, state badges and clear controls |
| Text editor/PIN dialogs | Same limits, validation and return values | Keyboard-safe glass sheets |
| Date/time pickers | Same bounds, times and return values | Expressive themed native picker surfaces |
| Snackbar, menus, tooltips | Same messages/actions | Central rounded tokens and contrast |
| Home widget | Same days, mood, tap destination | Layered colorful native widget, dark resources |
| Notifications | Message, Miss Me/reply, invites/responses, date/anniversary reminders, live-location ongoing indicator | Matching small icon/accent; channels, IDs, schedules, text and actions preserved |

Android owns permission prompts, biometric prompts, photo/file pickers and system notification placement; their native behavior is preserved. RemoteViews and notification surfaces use native, low-cost tinted fallbacks rather than unsupported backdrop blur.

## Implementation constraints

- Central six-family palette, typography, spacing, radii, contrast scrims and motion tokens.
- Outfit font bundled under SIL OFL, no runtime font requests.
- Native presentation-only channel reads Android SDK and wallpaper accent; Android 12+ uses wallpaper-derived tonal roles, with bundled fallback.
- At most two prominent blur layers in main chrome; chat trades the header blur for composer blur. Cards are tinted, not independent full-cost backdrop filters. Overlays suspend underlying route blur.
- Ambient mesh paints in an isolated layer at a low update rate; reduced motion disables drift, shimmer, particles and entrance movement.
- Same minimum Android 7, same keystore, universal ARMv7/ARM64 APK.
