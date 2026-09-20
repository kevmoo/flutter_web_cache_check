CLI and library to configure and audit HTTP caching headers and WebAssembly (`--wasm`) deployment artifacts for Flutter web applications using `--web-content-hash`.

## Commands

### `fb-config`

Injects or updates the canonical 5-rule Firebase Hosting `Cache-Control` stack (`max-age=0, must-revalidate` for root bootloaders, unhashed manifests, and `404.html`; `public, max-age=31536000, immutable` for hashed entrypoints and `assets/**`), tightens unguarded SPA catch-all rewrites, and configures `hosting.predeploy` with `flutter build web --wasm --web-content-hash`:

```sh
dart run bin/flutter_web_cache_check.dart fb-config --file firebase.json
# Or for JS-only builds without WebAssembly:
dart run bin/flutter_web_cache_check.dart fb-config --no-wasm --file firebase.json
```

### `check`

Performs a live HTTP caching and asset-graph audit against a deployed Flutter web URL:

- Verifies root bootloaders (`index.html`, `flutter_bootstrap.js`) and unhashed manifests (`AssetManifest.bin.json`) revalidate (`F-01`, `F-02`, `F-07`) and support `304 Not Modified` conditional requests (`R-01`, `R-02`).
- Checks `_flutter.buildConfig` for WebAssembly (`dart2wasm` / `mainWasmPath`) targets (`W-01`, opt-out via `--no-wasm`).
- Audits hashed `.wasm`, `.mjs`, `.js`, and hashed manifest assets for `immutable` 1-year caching (`F-03`, `F-04`), MIME types (`M-01` `application/wasm`, `M-02` `text/javascript`), and compression (`C-01`, `C-02`).
- Probes synthetic missing hashed paths (`/main.dart.00000000.js`, `/main.dart.00000000.wasm`, `/assets/__cache_check_missing__.00000000.png`) to catch SPA HTML rewrite traps (`F-05`) and negative-cache `404` poisoning (`F-06`).

```sh
dart run bin/flutter_web_cache_check.dart check https://example.web.app
```

## Empirical Redteam Harness (`tool/redteam_harness`)

The repository includes the empirical redteam simulator and CDP harness under `tool/redteam_harness/` (with `tool/sample_app/` and `tool/sample_pkg/`). Note that `tool/` is excluded from published `pub.dev` tarballs via `.pubignore`.

```sh
# Run fast unit and in-process Wasm/JS dogfood tests:
dart test -C tool/redteam_harness

# Run live S15 dogfood against a Flutter SDK checkout:
REDTEAM_FLUTTER_PHASE3=/path/to/flutter/bin/flutter \
  dart tool/redteam_harness/bin/redteam.dart --only S15 --out /tmp/redteam_s15
```
