# SwiftyTube

InnerTube package for iOS. Talk to YouTube's servers, resolve playable streams, mint PoTokens.

## Requirements

iOS 17+ / macOS 13+, Swift 5.9+, Xcode 16+. No third-party dependencies.

## Install

**File → Add Package Dependencies**, enter the repo URL:

```swift
.package(url: "https://github.com/686udjie/SwiftyTube.git", from: "0.0.2")
```

Add `SwiftyTube` to your target, then `import SwiftyTube`.

## Quick start

```swift
let tube = InnerTubeClient(config: .music) // or .youtube

let auth = try SessionImporter.importSession(from: cookieString)
await tube.loadState(from: myStore) // conforms to AuthStateProvider

let request = StreamResolveRequest.playback(videoId: id)
let result = try await StreamFallback.resolveFirstValid(
    request, using: tube, providers: .live
)
player.play(url: result.streamUrl)
```

Guest (signed-out) use works for public content - skip sign-in.

## What it covers

Transport (`browse`/`search`/`next`/`player`, likes, playlists, subs), stream resolution (format scoring, 9-client fallback, validation, caches), cipher (player.js, deobfuscation, n-transform, self-healing configs), PoToken minting, session import, Keychain helper. Details with examples: [Docs/Usage](Docs/Usage.md).

## What apps own

UI, response parsing, databases, settings, Keychain service names, playback. The library returns raw JSON or small models - you decide the rest.

## Resources

Static libraries can't bundle resources, so each app must embed these two files from `SwiftyTube/Resources/` (a synchronized folder does it automatically):

- `player_configs.json` - offline cipher configs
- `po_token.html` - PoToken minter page

## License

This repo is licensed under [GPLv3](https://github.com/686udjie/SwiftyTube/blob/main/LICENSE.txt). SwiftyTube is not affiliated with, endorsed, or sponsored by Google or YouTube.