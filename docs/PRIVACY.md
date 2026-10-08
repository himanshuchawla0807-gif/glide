# Privacy

Glide's maintainers receive no app data. There is no server, account signup, tracking, analytics, crash-report upload or automatic update service in this source release.

## Data and destinations

| Action | Data | Destination |
| --- | --- | --- |
| Pair Chrome | Random UUID for the chosen profile | Chrome local extension storage and macOS UserDefaults |
| Search with Return | Submitted query | Google Search in the paired Chrome profile |
| Open a URL | Submitted URL | The chosen website in Chrome |
| Enable Google suggestions | Current typed query, normal browser-managed Google cookies | Google's suggestion endpoint |
| Enable Chrome-history suggestions | Matching history titles and URLs | Local companion, local native app only |
| Enable saved Glide searches | Up to 20 submitted searches or URLs | macOS UserDefaults on the user's Mac |
| Enable launch-at-login | App registration | macOS Service Management |

All four optional toggles default off for fresh installations. Existing preferences survive upgrades. Suggestion queries are debounced. Google controls cookie handling and whether suggestions are personalized; Glide cannot promise the same ranking as Chrome's omnibox. The undocumented Google suggestion endpoint may change or fail. Local history can still work when Google suggestions fail.

No cookies are exported or decrypted. The app does not read Chrome's cookie or history databases. Queries are not written to application logs. Lifecycle and shortcut-status logs may exist locally in macOS.

## Local connection

Chrome launches a stdio native messaging helper restricted to the pinned companion extension origin. The helper connects to a local Unix socket; no network listener is exposed. The directory is owner-only, the socket and session file have mode 0600, and each app run uses a new random transport token. Frame sizes are bounded. Pairing requires an explicit companion click and approval in Glide. The random profile identifier distinguishes profiles without collecting email addresses.

The app writes its native-host registration to `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.himanshu.glide.json`. Its helper path points to the installed app. This is a local configuration file, not an upload.

## Removal

Disconnect the profile in Settings. Disable saved searches and click Clear if previously enabled. Remove Glide Companion from `chrome://extensions`, quit Glide and delete the app. Optional local cleanup is described in [Setup](SETUP.md). Removing the app does not delete your normal Chrome history or Google data; manage those through Chrome/Google.

The extension declares history access because history suggestions are available, even when the toggle is off. Its code requests history only when enabled. Site access is limited to `https://www.google.com/*`; there are no content scripts and no cookie permission. The companion does not inspect arbitrary page contents.

## Windows preview

Windows settings, paired profile identifier, native host manifest and a temporary session discovery file live under `%LOCALAPPDATA%\Glide`. The installed application normally lives in `%LOCALAPPDATA%\Programs\Glide`. Native host registration is under HKCU, without administrator permissions. The helper and app exchange framed messages over a random token-authenticated local named pipe. Other applications running as the same OS user are within the local trust boundary. There is no developer backend, telemetry, TCP listener or saved Glide query history in the Windows edition. The same opt-in Chrome-history and Google-suggestion flows apply. See [Windows setup](../windows/README.md).
