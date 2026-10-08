# Architecture

SwiftUI renders search, settings and the first-run connection screen. An AppKit nonactivating panel and Carbon hotkey keep the launcher available across spaces. Core Animation masks reveal the dropdown and expanding frosted boundary without continuous window reflow. Decorative animation pauses when hidden and respects Reduce Motion.

The app registers a native messaging host. Chrome's MV3 companion starts the stdio helper, which relays bounded length-prefixed JSON to the app over an owner-only Unix socket authenticated with a per-launch token. A random UUID stored in each extension profile is paired only after a toolbar click and local approval. The UUID is not an account credential and is never sent over the network.

The companion creates tabs in the paired profile's normal windows, preferring the last focused eligible window. Incognito is excluded. If none exists it creates a normal window. Launch Services starts the canonical Chrome app with the configured profile folder only when Chrome is not running.

History queries use the Chrome history API when enabled; Google suggestions use credentialed HTTPS fetches when enabled. HTTP/HTTPS destination validation is enforced on both sides. The app never calls developer-owned services.

Public visuals are original native implementations; supplied reference video and third-party component code are excluded. The extension ID is fixed by its public manifest key. No private signing key is needed or included.
