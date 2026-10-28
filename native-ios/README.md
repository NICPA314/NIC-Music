# NIC Music · Native iOS

Experimental SwiftUI frontend for the user's AMLL-based iOS player. This lives alongside the unmodified upstream Tauri project. Apple Music catalogue/account integration is future work.

## Current scope

- Native library, local search, mini player and full player; real SwiftUI Liquid Glass controls.
- Import supported local audio into the app sandbox; persist library; embedded title/artist/artwork.
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

Use the manual `Native iOS IPA` workflow on branch `native-ios`. It only builds this native app, not the upstream desktop matrix. IPA remains unsigned and must be signed for installation. Test bundle ID: `app.nicpa.amllplayer.test`; provisional app name: NIC Music.

## Not yet verified / limitations

Real-device import, background playback, remote controls, lyric synchronization, accessibility, rotation and appearance require testing. No streaming catalogue, automatic online lyrics, playlists editor, shuffle/repeat or licensed Apple Music playback is implemented. Empty library is real, not prefilled with fake working songs. Native decoding only supports formats AVAudioPlayer can read. Do not market this as official Apple Music.

The upstream root LICENSE contains AGPL-3.0, while its package.json says GPL-3.0; preserve notices and resolve that inconsistency before distribution rather than replacing upstream terms.
