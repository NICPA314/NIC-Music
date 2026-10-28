# NIC Music · Native iOS

Experimental SwiftUI frontend for the user's AMLL-based iOS player. This lives alongside the unmodified upstream Tauri project. Apple Music catalogue/account integration is future work.

## Current scope

- Native library, local search, mini player and full player; real SwiftUI Liquid Glass controls.
- Import supported local audio into the app sandbox; persist library; embedded title/artist/artwork.
- Import files or recursively import folders with visible progress and a per-file result. Titles come from embedded tags, never from filenames. Missing title tags produce an explicit failure.
- Library folder import groups nested audio directories as albums. A flat selection groups by album/album-artist tags. Later imports match existing albums and reuse their storage directory.
- Playlists keep independent audio copies under `Documents/Music/Playlists/<name-id>/`. The main library uses `Documents/Music/Albums/<artist>/<album>/`. Original audio bytes are preserved. Exact duplicate files are skipped only within the same destination.
- Numbered filenames determine playlist import order. Other tracks sort by artist, release date, album, disc and track number. The playback queue uses the displayed order.
- Embedded art takes precedence over adjacent `cover.jpg/jpeg/png/heic/webp`. Folder imports prefer same-stem TTML over LRC and recognize `tall_animated_artwork.mp4` (preferred), `portrait_animated_artwork.mp4`, `square_animated_artwork.mp4` and `cover.mp4`. All imported attachments remain available after source removal.
- Album details show available release date, label, copyright, genre and native audio quality; artist artwork can be set independently. Missing information is not synthesized.
- Lyrics translation and pronunciation switches use only data present in the lyric file. No automatic translation service is used.
- Play/pause, seek, previous/next, background audio and lock-screen commands.
- Import UTF-8 LRC or TTML for the selected song. AMLL Core runs locally in WKWebView and follows native playback time.
- `LyricsWeb/src/ttml-parser.ts` is reused from this repository's `packages/player/src/utils/ttml-parser.ts`; upstream attribution and root license are retained. Package dependencies carry their own licenses.

## Build

Xcode 26+ SDK and XcodeGen are required; deployment floor is iOS 26 so the same native material also runs on iOS 27+. This is not a claim of device verification on iOS 27.

```sh
cd native-ios/LyricsWeb
npm ci --ignore-scripts
npm run build
cd ..
xcodegen generate
xcodebuild build -project NICMusic.xcodeproj -scheme NICMusic -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO
```

Use the `Native iOS IPA` workflow on branch `native-ios` (manual or native-source push). It builds device and simulator targets, runs import/playback unit tests and a system document-picker UI test, and packages an unsigned IPA. Test bundle ID: `app.nicpa.amllplayer.test`.

Test fixtures are original synthetic ALAC tones and solid colors, generated with `python3 Tests/make_fixtures.py`. User audio, lyrics and UI references are not uploaded or bundled. Local Web QA also exercises TTML rendering, seek, LRC, translation and pronunciation controls.

## Not yet verified / limitations

Real-device file providers, background playback, remote controls, lyric synchronization, accessibility, rotation and appearance still require device testing. The automated fixture tests do not prove the reported original device failure is resolved. No streaming catalogue, automatic online lyrics, playlist reordering, shuffle/repeat or licensed Apple Music playback is implemented. Native decoding supports formats AVAudioPlayer can read. The deployment floor remains iOS 26.0; iOS 27 behavior has not been device-verified.

The upstream root LICENSE contains AGPL-3.0, while its package.json says GPL-3.0; preserve notices and resolve that inconsistency before distribution rather than replacing upstream terms.

Animated cover art uses the 3:4 tall video in the player when available; the upper image fades into a blurred artwork background. iOS 26 system Now Playing receives the matching 3:4 or 1:1 animated-artwork variant with its actual first-frame preview. Unsupported ratios keep static lock-screen artwork. Actual lock-screen animation remains subject to system support, device settings and device verification. See https://developer.apple.com/documentation/mediaplayer/providing-animated-artwork-for-media-items .
