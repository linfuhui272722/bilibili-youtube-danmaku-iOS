# B2Y Danmaku (iOS)
它并不能工作，这是失败的尝试，但我还是想聊一下
> Sync Bilibili 弹幕 onto the YouTube iOS app — a jailbreak tweak port of the [bilibili-youtube-danmaku](https://github.com/ahaduoduoduo/bilibili-youtube-danmaku) browser extension.

This is the **iOS jailbreak** port. It hooks the native YouTube app (`com.google.ios.youtube`) using [Theos](https://theos.dev) + [Logos](https://theos.dev/docs/logos-syntax), fetches the matching Bilibili web danmaku stream, and overlays it on top of the YouTube player.

## How it works

```
┌─────────────────────────────────────────────────────────────┐
│  YouTube iOS app (com.google.ios.youtube)                  │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  YTPlayerViewController                               │  │
│  │  ├─ contentVideoID  ──► B2YDanmakuEngine               │  │
│  │  ├─ playerData     ──► (title, duration)               │  │
│  │  └─ activeVideo    ──► (currentMediaTime, poll 10 Hz)  │  │
│  │                          │                             │  │
│  │  ┌──────────────────────▼───────────────────────────┐  │  │
│  │  │  B2YDanmakuOverlayView (UIView, CADisplayLink)    │  │  │
│  │  │  ├─ track-based layout                           │  │  │
│  │  │  ├─ scrolling / top / bottom danmaku             │  │  │
│  │  │  └─ label pool (recycled)                        │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────┘  │
│                          ▲                                  │
│                          │ NSURLSession                     │
│  ┌───────────────────────┼───────────────────────────────┐  │
│  │  B2YDanmakuAPI (Bilibili web API)                      │  │
│  │  ├─ WBI key fetch + signature (MD5)                    │  │
│  │  ├─ search/all/v2  ──► keyword search (WBI-signed)     │  │
│  │  ├─ view           ──► video info (cid, aid, duration) │  │
│  │  └─ dm/wbi/web/seg.so ─► protobuf danmaku segments     │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Data flow

1. **Video detection** — The Logos hook on `YTPlayerViewController` fires when a video becomes active. We read `contentVideoID` and the player response's `videoDetails.title`.

2. **Bilibili search** — The title is sent to Bilibili's `search/all/v2` endpoint (WBI-signed). Results are scored by Levenshtein similarity; ties are broken by danmaku count (mirrors the extension's `order: 'dm'`).

3. **Danmaku download** — For the matched BV id, we fetch `view` to get the `cid`, then download every 6-minute `seg.so` segment (raw protobuf). Segments are fetched sequentially with a 300 ms delay to avoid rate-limiting.

4. **Protobuf parsing** — A hand-rolled 200-line parser extracts `progress`, `mode`, `color`, `fontsize`, `content`, `weight` from each `DanmakuElem`. No protobuf runtime dependency.

5. **Rendering** — A `CADisplayLink` drives a 60 FPS loop on `B2YDanmakuOverlayView`. Danmaku are emitted when the player's `currentMediaTime` crosses their `progress`. Scrolling danmaku claim a horizontal track until their tail clears the right edge; top/bottom danmaku claim a track for 4 seconds.

## Features

- ✅ Auto-match by title (Levenshtein similarity, configurable threshold)
- ✅ Manual BV id mode (for when auto-match fails)
- ✅ Optional SESSDATA cookie for logged-in search (higher rate limits)
- ✅ Scrolling (mode 1/2/3/6/7), top-fixed (mode 5), bottom-fixed (mode 4) danmaku
- ✅ Configurable font size, opacity, scroll speed, display area
- ✅ Low-weight danmaku filter
- ✅ Settings integrated into YouTube's own settings panel
- ✅ Rootful / rootless / roothide builds via Codemagic CI

## Requirements

### Build

- macOS (Codemagic `mac_mini_m1` or local Mac)
- [Theos](https://theos.dev/docs/installation) (`git clone --recursive https://github.com/theos/theos.git`)
- iPhoneOS SDK 16.5 (downloaded automatically by the CI pipeline)
- Xcode command-line tools (for `clang`)

### Runtime

- A jailbroken iOS device (arm64 / arm64e)
- YouTube app installed (tested on YouTube 19.x)
- A jailbreak package manager (Sileo / Zebra / Filza)
- Internet access (to reach `api.bilibili.com`)

## Building locally

```bash
# 1. Install Theos
export THEOS=~/theos
git clone --recursive https://github.com/theos/theos.git "$THEOS"

# 2. Install the iPhoneOS SDK
mkdir -p "$THEOS/sdks"
cd /tmp
curl -L -o sdk.tar.xz \
  "https://github.com/theos/sdks/raw/master/iPhoneOS16.5.sdk.tar.xz"
tar -xf sdk.tar.xz -C "$THEOS/sdks"

# 3. Build (pick one)
cd /path/to/B2YDanmaku
make package                              # rootful
make package ROOTLESS=1                   # rootless (Dopamine / palera1n)
make package ROTHIDE=1                    # roothide (RootHide)

# 4. Install
# Transfer packages/B2YDanmaku_*.deb to your device, then:
dpkg -i B2YDanmaku_*.deb   # rootful / roothide
# or add the .deb to Sileo as a local source (rootless)
```

## Building with Codemagic

This repo ships a [`codemagic.yaml`](./codemagic.yaml) that automates the entire build:

1. Push the repo to your GitHub.
2. In [Codemagic](https://codemagic.io), create a new project and select the repo.
3. Codemagic will auto-detect `codemagic.yaml`.
4. Click **Start new build** — the pipeline will:
   - Install Theos + the iPhoneOS SDK
   - Build three `.deb` files (rootful, rootless, roothide)
   - Publish them as downloadable artifacts
5. Download the `.deb` matching your jailbreak type and install on-device.

No Apple Developer account or code signing is required — jailbreak tweaks are unsigned `.deb` packages.

## Configuration

Open YouTube → Settings → scroll to **B2Y Danmaku**:

| Setting | Description | Default |
|---|---|---|
| Enable Danmaku | Master toggle | On |
| Auto-match by Title | Search Bilibili by the YouTube video title | On |
| Manual BV ID | Use a specific BV id instead of auto-match | (empty) |
| Bilibili SESSDATA | Cookie for logged-in search (optional) | (empty) |
| Match Threshold | Minimum title similarity to accept a match | 60% |
| Display Area | Vertical portion of the player covered | 75% |
| Font Size | Danmaku font size | 18pt |
| Opacity | Danmaku text opacity | 100% |
| Scroll Speed | Scrolling danmaku speed (pts/s) | 100 |
| Filter Low-Weight Danmaku | Drop danmaku below the weight threshold | Off |
| Reset All Settings | Wipe every B2Y preference | — |

## How matching works

The original browser extension searches Bilibili by the YouTube video title and picks the best result. We port that logic verbatim:

1. **Normalise** both titles — strip bracketed annotations (`(4K)`, `[Official MV]`, `【字幕】`), strip emoji, lowercase, collapse whitespace.
2. **Score** every search result with Levenshtein similarity (0–100%).
3. **Filter** to results above the threshold (default 60%).
4. **Tie-break** by danmaku count (most danmaku wins, matching the extension's `order: 'dm'`).

If no result clears the threshold, no danmaku is loaded (the YouTube video plays normally). You can override this by entering a manual BV id.

## Limitations & known issues

- **Title mismatch** — If the Bilibili and YouTube uploads have very different titles (e.g. localized vs. original), auto-match may fail. Use the manual BV id in that case.
- **Time offset** — Bilibili and YouTube uploads may have slightly different start points (intro cards, etc.). A time-offset setting is planned but not yet implemented.
- **Cookie sharing** — The SESSDATA cookie must be pasted manually; we don't embed a Bilibili login webview (to keep the tweak small). Anonymous search works for most public videos.
- **YouTube version drift** — The hooks target `YTPlayerViewController`, `YTPlayerView`, `YTMainAppVideoPlayerOverlayViewController`, and `YTWatchViewController`. If YouTube renames these in a future update, the hooks will silently no-op (the app won't crash, but danmaku won't appear). Check the console log for `[B2YDanmaku]` messages.
- **arm64e only** — Modern devices (A12+) use arm64e; the Makefile builds both `arm64` and `arm64e` so older devices are covered too.

## Architecture reference

This project draws structural inspiration from [YTLite](https://github.com/dayanch96/YTLite) (hook layout, settings panel pattern, Theos Makefile conventions) but does **not** share any code with it. The danmaku fetching logic is a direct port of the original [bilibili-youtube-danmaku](https://github.com/ahaduoduoduo/bilibili-youtube-danmaku) browser extension's background script.

| Browser extension (JS) | iOS tweak (Obj-C) |
|---|---|
| `entrypoints/background/index.js` (WBI, search, view, seg.so) | `Bilibili/B2YWBIKeys.m`, `Bilibili/B2YDanmakuAPI.m` |
| `lib/protobuf-parser.js` | `Bilibili/B2YProtobufParser.m` |
| `utils/danmaku-engine.js` (track layout, animation) | `Engine/B2YDanmakuOverlayView.m` |
| `entrypoints/content/index.js` (YouTube DOM hooks) | `B2YDanmaku.x` (YouTube class hooks) |
| `entrypoints/popup/popup.js` (settings UI) | `Settings.x` (YouTube settings panel) |

## File structure

```
B2YDanmaku/
├── Makefile                  Theos build config (rootful/rootless/roothide)
├── control                   Debian package metadata
├── B2YDanmaku.plist          MobileSubstrate filter (com.google.ios.youtube)
├── codemagic.yaml            CI/CD pipeline
├── B2YDanmaku.h              Central header (imports + YouTube class decls)
├── B2YDanmaku.x              Main Logos hooks (player view controller)
├── Settings.x                Settings panel injected into YouTube settings
├── Bilibili/
│   ├── B2YWBIKeys.h/.m       WBI signature (mixin key + MD5)
│   ├── B2YDanmakuAPI.h/.m    Search / view / seg.so client
│   ├── B2YProtobufParser.h/.m  Hand-rolled protobuf reader
│   └── B2YDanmakuModel.h/.m  B2YBilibiliVideo + B2YDanmaku value types
├── Engine/
│   ├── B2YDanmakuEngine.h/.m  Coordinates API + overlay, owns danmaku list
│   └── B2YDanmakuOverlayView.h/.m  UIView + CADisplayLink renderer
├── Utils/
│   ├── B2YSettings.h/.m       NSUserDefaults wrapper (b2y_* keys)
│   ├── B2YMD5.h/.m            CommonCrypto MD5 wrapper
│   └── B2YVideoMatcher.h/.m  Title normalisation + Levenshtein
└── Resources/                 (bundle resources, currently empty)
```

## License

MIT — see [LICENSE](./LICENSE).

## Credits

- Original browser extension: [ahaduoduoduo/bilibili-youtube-danmaku](https://github.com/ahaduoduoduo/bilibili-youtube-danmaku)
- iOS tweak structure reference: [dayanch96/YTLite](https://github.com/dayanch96/YTLite)
- Build system: [Theos](https://theos.dev)
- WBI signature algorithm: [Bilibili API documentation](https://github.com/SocialSisterYi/bilibili-API-collect)

## Contributing

PRs welcome. Particularly useful contributions:

- **Time-offset setting** — let users nudge danmaku timing ±N seconds to compensate for intro differences.
- **Bilibili login webview** — embed a `WKWebView` in settings so users can log in to Bilibili and grab the SESSDATA automatically.
- **YouTube version resilience** — add fallback hooks for when YouTube renames its player classes.
- **Localization** — the settings panel is English-only; we'd love i18n contributions.
