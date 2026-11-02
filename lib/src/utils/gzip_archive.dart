import 'dart:typed_data';

import 'package:archive/archive.dart';

Uint8List gzipEncode(Uint8List bytes) => Uint8List.fromList(GZipEncoder().encode(bytes));

Uint8List gzipDecode(Uint8List bytes) => Uint8List.fromList(GZipDecoder().decodeBytes(bytes));
