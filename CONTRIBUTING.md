# Contributing

Build with `zsh build.sh` and run `zsh test.sh`. Keep the source release runnable with Apple Command Line Tools alone. Do not add telemetry, account requirements, remote configuration, or default-on query transmission. Discuss new permissions before adding them.

Verify UI changes with Reduce Motion on and off, Unicode input, IME input, rapid typing, keyboard navigation, and dismissal during transitions. Chrome changes should verify normal-window reuse, incognito exclusion, multiple profiles, cold-start, disconnect/reconnect and offline history. Use disposable browser profiles for testing; never commit cookies, search history, UUIDs, local session tokens or personal screenshots.

Do not change the manifest key without documenting the migration. Keep setup, privacy and permission documentation aligned with code. CI's Chrome API tests use mocks; report what was actually tested on real macOS and Chrome when submitting changes.
