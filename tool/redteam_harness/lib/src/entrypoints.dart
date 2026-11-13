// Copyright (c) 2026, Kevin Moore. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

final RegExp _lowerHex8 = RegExp(r'^[0-9a-f]{8}$');

/// Whether [name] is a compiled `main.dart` entrypoint basename (unhashed or
/// with an 8-character lowercase hex content hash).
///
/// When [jsOnly] is `true`, only `.js` entrypoints match (excluding `.wasm` and
/// `.mjs`), matching the pre-Flutter 3.38 legacy service worker `CORE` list.
bool isMainEntrypoint(String name, {bool jsOnly = false}) =>
    switch (name.split('.')) {
      ['main', 'dart', 'js'] => true,
      ['main', 'dart', 'wasm' || 'mjs'] => !jsOnly,
      ['main', 'dart', final h, 'js'] => _lowerHex8.hasMatch(h),
      ['main', 'dart', final h, 'wasm' || 'mjs'] =>
        !jsOnly && _lowerHex8.hasMatch(h),
      _ => false,
    };
