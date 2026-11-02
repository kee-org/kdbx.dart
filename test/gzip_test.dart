import 'dart:math';
import 'dart:typed_data';

import 'package:kdbx/src/utils/gzip.dart';
import 'package:kdbx/src/utils/gzip_archive.dart' as archive_impl;
import 'package:test/test.dart';

// Runs on the VM and in the browser (`dart test -p chrome`, optionally `--compiler dart2wasm`). On the VM the default
// implementation is the native one so this also proves that both implementations are interchangeable.
void main() {
  final random = Random(42);
  final samples = <String, Uint8List>{
    'empty': Uint8List(0),
    'one byte': Uint8List.fromList([7]),
    'text': Uint8List.fromList(('<KeePassFile>' * 500).codeUnits),
    'random': Uint8List.fromList(List.generate(100000, (_) => random.nextInt(256))),
  };

  group('default implementation', () {
    samples.forEach((name, bytes) {
      test('round trip: $name', () {
        expect(gzipDecode(gzipEncode(bytes)), bytes);
      });
    });
  });

  group('archive implementation', () {
    samples.forEach((name, bytes) {
      test('round trip: $name', () {
        expect(archive_impl.gzipDecode(archive_impl.gzipEncode(bytes)), bytes);
      });
      test('default implementation reads what archive writes: $name', () {
        expect(gzipDecode(archive_impl.gzipEncode(bytes)), bytes);
      });
      test('archive reads what the default implementation writes: $name', () {
        expect(archive_impl.gzipDecode(gzipEncode(bytes)), bytes);
      });
    });
  });
}
