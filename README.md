# Us couples app

The existing private Flutter space for two, using Supabase, Firebase and WebRTC.

The v1.10 development candidate adds on-phone ECHO models for Android, alongside opt-in, self-hosted ECHO answering and repairs chat AI/media issues. Automatic answering is disabled by default and requires prepared phone models or an explicitly selected running Mac bridge.

- [Phone setup for Pixel 8 and 6 GB Android](docs/ECHO_PHONE.md)
- [Phone validation and remaining device checks](docs/ECHO_PHONE_VALIDATION.md)
- [Optional Mac setup, cost and privacy](docs/ECHO_SETUP.md)
- [Candidate changes](docs/ECHO_CHANGELOG.md)
- [Validation and limitations](docs/ECHO_VALIDATION.md)
- [Previous v1.8 verification](docs/VALIDATION_1_8_0.md)

Use the existing signed Android validation workflow. Never commit signing material, server keys or bridge session files. This branch does not replace the existing application or database.
