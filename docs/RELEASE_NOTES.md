Us 1.5.0 — a colorful new home for two

- Full Flutter presentation redesign: six harmonious accent families, warm light and deep-ink dark themes, oversized Outfit typography, expressive flower shapes, a colorful bento Home and floating five-tab glass dock.
- Real clipped backdrop blur on Android 12+, tinted fallbacks on older phones, wallpaper-derived Material tonal roles, glass editors and confirmation sheets, gradient chat bubbles and a floating composer.
- Redesigned sign-in, pairing, lock, Home, chat, calendar, memories and composer, settings, lists, journal, letters, expenses, collections and live-location screens. Matching native launch icon, splash, widget and notification accents.
- Spring press and navigation feedback, staggered entrances, animated counters/rings, photo Hero transitions, shimmer loading, gentle celebration particles and reduced-motion support. Predictive back is enabled on supported Android versions.
- The memory composer keeps Save and retry feedback within reach. Existing collection selection, create/move/delete, reactions and all existing actions remain available.
- UI-only scope: frozen services, persistence, backend files and route destinations verified unchanged. No new accounts, configuration or billing needed. Same Android package and signing key: install over Us 1.2.0 without uninstalling.

Dependencies: Flutter SDK flutter_localizations and bundled Outfit variable font under SIL OFL. No new third-party SDK, paid service, ads, games or analytics.

Validation: static analysis and all 103 Flutter tests pass, with 90 light/dark, compact RTL/large-text and tablet layout captures. The exact signed APK passes signature/ARM checks, upgrades over Us 1.2.0, reaches login and handles an OAuth denial callback without crashes on Android 7 and Android 15 emulators. Validation metadata is recorded in release-ready.json. Real-device 60/120 fps performance, successful Google account sign-in, FCM delivery, hardware GPS, pinned home-widget rendering and vendor background behavior were not measured. Android-owned permission, biometric and notification layouts remain native. Photo viewing has shared-element motion; other destinations use expressive entrance and native back transitions rather than a custom shared-element transform for every card.
