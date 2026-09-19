## 0.0.2-wip

- Segment live URL checks into General HTTP/Flutter Web invariants (`G-01`–`G-08`) and a Firebase Hosting adapter (`FB-01`–`FB-02`, `--platform=[auto|firebase|generic]`).
- Fix false-pass substring checks in `CacheDirectives` (`max-age=3600` and `must-revalidate`), enforce `.wasm` (`application/wasm`) and `.mjs`/`.js` MIME types, validate `br`/`gzip` compression + `Vary: Accept-Encoding`, and probe SPA catch-all rewrite poisoning (`F-05`) and 404 negative caching (`F-06`).
- Update `fb-config` to emit the 5-rule `last-match-wins` `firebase.json` header stack (`max-age=0, must-revalidate` base + `404.html` guard + `assets/**` immutable with unhashed manifest override) and tighten unguarded `"**"` SPA rewrites.

## 1.0.0

- Initial version.
