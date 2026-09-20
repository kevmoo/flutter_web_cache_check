## 0.0.2-wip

- Add first-class WebAssembly (`dart2wasm`) target detection (`W-01`, `--[no-]wasm`) in `UrlChecker` and `check` CLI.
- Probe synthetic missing `.wasm` hashed entrypoints (`/main.dart.00000000.wasm`) for SPA HTML rewrite traps (`F-05`) and negative-cache `404` poisoning (`F-06`) (`W-02`).
- Add `FirebaseConfig.applyUpdates` and `--[no-]wasm` support to `fb-config` (`W-03`), defaulting `hosting.predeploy` to `flutter build web --wasm --web-content-hash` and preserving `--wasm` when upgrading existing predeploy hooks.
- Consolidate the `flutter_web_cache_redteam` simulator and empirical test harness into `tool/redteam_harness`, deriving `HostingServer.firebaseRules` directly from `FirebaseConfig.defaultHeaders` (`M-01`, `M-02`, `M-03`).
- Segment live URL checks into General HTTP/Flutter Web invariants (`G-01`–`G-08`) and a Firebase Hosting adapter (`FB-01`–`FB-02`, `--platform=[auto|firebase|generic]`).
- Fix false-pass substring checks in `CacheDirectives` (`max-age=3600` and `must-revalidate`), enforce `.wasm` (`application/wasm`) and `.mjs`/`.js` MIME types, validate `br`/`gzip` compression + `Vary: Accept-Encoding`, and probe SPA catch-all rewrite poisoning (`F-05`) and 404 negative caching (`F-06`).
- Update `fb-config` to emit the 5-rule `last-match-wins` `firebase.json` header stack (`max-age=0, must-revalidate` base + `404.html` guard + `assets/**` immutable with unhashed manifest override) and tighten unguarded `"**"` SPA rewrites.

## 0.0.1

- Initial version.
