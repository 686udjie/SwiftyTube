# SwiftyTube Usage

Every snippet assumes `import SwiftyTube`.

## Client

```swift
let tube = InnerTubeClient(config: .music)   // YouTube Music
let tube = InnerTubeClient(config: .youtube) // YouTube

await tube.updateLocale(YouTubeLocale(gl: "DE", hl: "de")) // change region anytime
```

## Sign-in

```swift
let auth = try SessionImporter.importSession(from: cookieString)
// persist auth.cookies / .sapisid / .visitorData / .dataSyncId your way
await tube.loadState(from: store) // re-call after login/logout; store has 4 getters
```

## Browse, search, player

Raw JSON in, your models out. All calls take optional `client:` / `locale:` overrides.

```swift
let home = try await tube.browse(browseId: "FEmusic_home")
let page2 = try await tube.browse(continuation: token)
let results = try await tube.search(query: "lofi")
let upNext = try await tube.next(videoId: id, playlistId: playlist)
let typed: PlayerResponse = try await tube.playerResponse(videoId: id)

// Collect all pages instead of handling continuations by hand:
let items = try await tube.paginate(
    browseId: "FEmusic_liked_playlists",
    parse: { MyParser.items(from: $0) },
    continuation: { MyParser.token(from: $0) }
)
```

## Library and account

```swift
try await tube.like(videoId: id)
try await tube.unlike(videoId: id)
try await tube.feedback(tokens: [token]) // library add/remove
try await tube.editPlaylist(
    playlistId: id,
    actions: PlaylistEditAction.dictionaries([.addVideo(videoId: id)])
)
try await tube.createPlaylist(title: "Gym")
try await tube.deletePlaylist(playlistId: id)
try await tube.subscribe(channelId: id)
try await tube.unsubscribe(channelId: id)
let me = try await tube.accountInfo() // name, email, avatar
```

`.addVideo(videoId:setVideoId:)`, `.removeVideo(setVideoId:)`, `.renamePlaylist(name:)` build the action dicts. Pair local-then-remote writes with `OptimisticMutation.attemptingRemote(remote, rollback:)`.

## Play a stream

Walks the fallback chain, mints PoTokens lazily, validates, caches - returns the first working stream:

```swift
var request = StreamResolveRequest.playback(videoId: id)
request.options.audioQuality = .high
let result = try await StreamFallback.resolveFirstValid(
    request, using: tube, providers: .live
)
// result.streamUrl, .title, .author, .duration, .loudnessDb, ...

let download = StreamResolveRequest.download(videoId: id) // no cache, AAC preferred
```

`.live` wires the shared cipher fetcher, WebView, config store, and format tracking. Add yours:

```swift
var providers = StreamResolveProviders.live
providers.poTokenProvider = { videoId in
    try? await PoTokenGenerator.shared.generate(videoId: videoId, sessionId: mySessionId)
}
providers.resolvedFormatHandler = { info in
    // persist info.itag / .mimeType / .playbackUrl for tracking
}
```

One client, no loop:

```swift
let result = try await StreamResolver.resolve(
    videoId: id, client: .androidVr1_65_10, using: tube, providers: providers
)
let ok = await StreamResolver.validateStream(url: result.streamUrl)
```

## Video streams

```swift
switch try await StreamFallback.resolveVideo(request, using: tube, providers: providers) {
case .muxed(let url):
    play(url)
case .split(let video, let audio, _):
    playEDL(video, audio) // or StreamFallback.combineVideoAndAudio(videoURL:audioURL:duration:)
}
```

## Durations

Never throws - cached value, fresh fetch, or nil while another task fetches:

```swift
if let seconds = await tube.resolveDuration(videoId: id) { ... }
// completion posts NotificationCenter .durationDidUpdate with ["videoId": id]
```

## PoTokens and cipher (standalone)

```swift
let tokens = try await PoTokenGenerator.shared.generate(videoId: id, sessionId: sid)
// tokens.playerRequestPoToken → /player body, .streamingDataPoToken → &pot=

let sts = try await PlayerJsFetcher.shared.getSignatureTimestamp()
let url = try await CipherExecutor.shared.resolveCipherURL(
    cipherText: cipher, playerJs: js, playerHash: nil
)
let config = await PlayerConfigStore.shared.config(for: hash)
```

`po_token.html` must be embedded in your app bundle (see README).

## Parsing helpers

Nil instead of crashes:

```swift
InnerTubeJSON.runsText(dict)              // joined runs, falls back to simpleText
InnerTubeJSON.runsTexts(dict)             // all run texts minus separators
InnerTubeJSON.lastThumbnailURL(list)      // largest thumbnail
InnerTubeDecode.dict(at: ["contents", "x"], in: json)
InnerTubeDecode.string(at: [...], in: json)
InnerTubeDecode.intFromStringOrInt(value) // String-or-Int fields
InnerTubeDecode.continuationToken(in: shelf)
```

## Keychain, HTTP, logging

```swift
let store = SecureStore(service: "com.myapp.session")
try store.save(data, for: "key")
let data = try store.load(for: "key") // throws .notFound when missing

let (data, response) = try await HttpClient.validatedData(for: request)
try await RetryPolicy.innerTube.run({ try await fetch() }, isRetryable: { _ in true })

SwiftyTubeLog.handler = { message, level in myLogger.log("\(level): \(message)") }
// default forwards to os.Logger, subsystem "SwiftyTube"
```
