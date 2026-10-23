# AI in the chat composer

All nine existing AI tools are available beside the message box using the sparkle button. Chat no longer opens the separate AI screen or uses a header shortcut. The separate screen remains available to the memory and expense features.

## Behavior

- Write requests, messages to rewrite, expense descriptions, and memory descriptions in the real message field. Reply, summary, and plan extraction supply a useful default instruction when that field is empty.
- Choose an action, language, and any required saved messages, date range, budget, or duration in the inline panel. Long-press reply assistance and `@Us ` requests also open this panel. Reply assistance preserves the reply target.
- Generate inserts the first suggestion or a readable structured plan directly into the message field. Alternatives replace that text. Undo restores the original draft and selection. Responses never send a chat message automatically. Inserted text follows the chat’s existing encrypted local draft persistence.
- If text changes while a request is in flight, the response waits for an explicit Use result or option selection. Closing the panel discards a pending result. Identity changes close the panel and invalidate results.
- Dates, tasks, and expenses have a separate Review & save to Us action using the existing editable forms. Opening review does not save. Save locks during review/write and disables after success.
- Both partners must consent before using shared chat. Rewrites, date ideas, expense descriptions, and captions use only the request text. The panel exposes opt-in, revocation, refresh, context coverage, and source lookup. Its message picker excludes hidden, deleted, pending, and attachment messages, and applies changes only on confirmation.
- Layout adapts to the actual available height. Call shortcuts, profile subtitle, and historical shared answers collapse while composing with AI or in short viewports; the message list and tools share the remaining space. The input stays above the keyboard and dock. Message timestamps wrap at large text sizes.

## Server contract and rollout

Deploy `supabase/functions/us-ai` together with its `logic.ts` update before distributing the new app. No database migration, provider change, new credentials, or quota increase is required.

The client sends wire action `ask` for a private Ask AI together request. The server normalizes it to the existing together task for context, consent, and inference, but **never publishes** that action, even if `publish: true` is supplied. An older backend rejects this unfamiliar action before inference instead of accidentally posting a private draft. The existing `together` wire action retains its Ask & share behavior for old clients and for the explicitly labelled standalone screen. Other requests send `publish: false` by default.

The API now identifies whether an answer was published and accurately describes text-only requests as using no chat history. Existing authenticated-user checks, caller-scoped message reads, consent recheck after inference, bounded context, quota reservation, and provider timeout remain in place.

## Bugs addressed

- Detached chat AI navigation and results without an editable message draft.
- Automatic publication of new composer Ask together requests.
- Missing useful composer text for structured dates, tasks, and expenses.
- Late responses overwriting newer text; losing new text entered while sending.
- Missing local UTF-8 byte validation (especially Tamil), context-selection validation, and summary-range validation.
- Raw Edge Function errors and malformed response handling; client requests without a deadline.
- Hidden/pending/media context options, unintended selection changes on picker dismissal, and duplicate save reviews.
- Stale permission loads after identity changes and permission refresh failures.
- Narrow-screen message status overflow and keyboard/composer crowding.

## Design references

The interaction draws on [Samsung Writing Assist](https://www.samsung.com/us/support/answer/ANS10000943/) for writing tools located at the input, and [Apple Writing Tools](https://support.apple.com/en-gb/guide/iphone/iph6f08da1d2/26/ios/26) for editable rewrites and Undo. Styling uses the app's existing Flutter theme.

## Verification

Run:

```sh
flutter analyze --no-fatal-infos
flutter test
node --test supabase/functions/us-ai/logic.test.ts
python3 scripts/check_ui_scope.py
```

The new tests exercise all nine actions, real message insertion and sending, alternatives/Undo, late responses, dismissal, input bounds, provider errors, consent, message filtering, explicit draft saves, and narrow light/dark layouts with 1.5x text and an open keyboard. Local HTTP tests exercise the actual Supabase Dart invocation and error handling, including the private wire action. Server tests cover private/legacy publication semantics as well as existing validation and output checks.

Screenshot artifacts are generated at `ui-review/chat-ai-light.png` and `ui-review/chat-ai-dark.png` (ignored by Git). The initial feature implementation was verified locally. The subsequent launch deployed the backend and verified live inference plus the signed Android build; see [v1.8.0 release verification](VALIDATION_1_8_0.md). Physical-device checks were not performed. Existing Tamil/Tanglish beta and keyword-recall limitations still apply.

Validated locally with Flutter 3.47.7 / Dart 3.13.5: **152 Flutter tests passed**, **8 server logic tests passed**, UI scope check passed, and analyzer reported no errors or warnings (four pre-existing informational notices in core files). The Linux test runtime needed a local `libsqlite3.so` alias pointing to the installed `libsqlite3.so.0`; this was an environment-only adjustment outside the repository.
