import 'dart:io';
import 'dart:typed_data';

// The native zlib is faster than the pure Dart implementation.
Uint8List gzipEncode(Uint8List bytes) => Uint8List.fromList(gzip.encode(bytes));

Uint8List gzipDecode(Uint8List bytes) => Uint8List.fromList(gzip.decode(bytes));
