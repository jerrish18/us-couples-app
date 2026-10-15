Us 1.2.0 — a fresh home for your story

- New iPhone-inspired design across the app: porcelain light and charcoal dark surfaces, lavender/rose accents, layered cards, a floating five-tab dock, cleaner page headers and feature tiles.
- Short eased page entrances and tab transitions, respecting Android's reduced-motion preference. Memory cards are built lazily, and photo decoding is bounded to avoid loading full-resolution images while scrolling.
- A dedicated memory composer previews your photo and asks for caption, date and collection. Choose an existing collection, create one immediately, or keep the memory without a collection.
- Tap your uploaded memory's three-dot menu → Delete memory. A confirmation explains that deletion removes it for both people. The server verifies the uploader and couple membership, removes the actual private Storage object, and deletes the row and reactions. Move to collection remains available.
- Same Android package and signing certificate, so install this APK over Us 1.1.0 without uninstalling.

Validation: live backend integration tests passed using temporary synthetic accounts, including memory save/delete, real Storage removal, partner authorization and third-account isolation. Flutter tests cover composer selection, new collection creation and saving retry. The exact signed release APK is checked for signature, ARMv7/ARM64 and Android 7 compatibility, installed over 1.1.0, and launched on an Android 7 emulator before publication.

Physical-device FCM delivery, successful Google account sign-in, hardware GPS, vendor background limits and scrolling frame rate were not measured in this release. No music/video integrations, ads, games, analytics or paid services were added.
