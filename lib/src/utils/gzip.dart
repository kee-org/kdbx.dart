import 'dart:typed_data';

import 'gzip_archive.dart' if (dart.library.io) 'gzip_io.dart' as impl;

/// gzip helpers that work on every platform. `dart:io` is not available on the web so the pure Dart implementation from
/// `package:archive` is used there.
Uint8List gzipEncode(Uint8List bytes) => impl.gzipEncode(bytes);

Uint8List gzipDecode(Uint8List bytes) => impl.gzipDecode(bytes);
