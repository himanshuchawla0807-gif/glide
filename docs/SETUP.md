# Setup and troubleshooting

Follow the README steps in order: build, install in Applications, launch, load the unpacked companion in the desired Chrome profile, click the companion, approve pairing, then set the profile directory from chrome://version.

## Not connected

Keep Glide running. Confirm the companion is enabled in the correct profile and click its toolbar action. Approve the pending request in Glide. If Chrome reports a native-host error, relaunch the installed app so it registers its current path. On macOS folder-access failure, use the folder chooser in Settings to select `~/Library/Application Support/Google/Chrome` and retry. Do not choose a single profile folder.

Loading the unpacked companion requires Chrome Developer mode. There is no Chrome Web Store listing in this source release. Enterprise Chrome policies may prohibit unpacked extensions or native messaging; Glide cannot override them.

## Wrong profile or Chrome cold start

Disconnect, click the companion in the desired profile and approve it. Set the profile directory to the last component of Profile Path on that profile's chrome://version page (`Default` or `Profile N`). Chrome must remain at `/Applications/Google Chrome.app` for the current launcher. Cold-start waits for the companion for roughly eight seconds; slower starts may need a second attempt.

## Shortcut conflict

Another launcher can own Shift + Space. Disable that conflicting binding or use Glide's menu-bar item. This release does not provide a custom shortcut editor.

## Suggestions missing

The empty state intentionally has no history. Enable Google suggestions or Chrome-history suggestions in Settings. History appears only for matching input. Google may return no personalized suggestions even while signed in. Google cookies stay in Chrome, and its endpoint is not a guaranteed API.

## Updates

Quit Glide, rebuild, replace the installed app, reopen it and reload the unpacked companion in chrome://extensions. Preserve the same installed path and extension ID to keep pairing. The public edition differs from the original personal build; pair it once when migrating.

## Uninstall local files

After quitting and removing the companion, delete the app. If desired, remove `~/Library/Application Support/Glide` and the single native-host file `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.himanshu.glide.json`. Do not remove Chrome's entire NativeMessagingHosts folder. `defaults delete com.himanshu.glide` removes Glide preferences, including paired ID, themes and saved searches. These cleanup steps are optional and user-controlled.

## Distribution limits

This source release is ad-hoc signed. macOS may require approving a locally built app in System Settings depending on quarantine and policy. Do not globally disable Gatekeeper. Maintainers have not notarized prebuilt binaries. Intel support compiles from source but has not been verified on physical Intel hardware. Live Chrome cold-start and clean-install pairing still need broader user testing; mocked tests are not a substitute for those checks.
