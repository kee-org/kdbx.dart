import 'dart:typed_data';

import 'package:argon2_ffi_base/argon2_ffi_base.dart';
import 'package:crypto/crypto.dart';
import 'package:kdbx/kdbx.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

/// A quick stand-in so the test does not need the native library or spend seconds in pure Dart Argon2. It is not
/// secure and never used outside this test.
class _FakeArgon2 extends Argon2 {
  @override
  bool get isFfi => false;
  @override
  bool get isImplemented => true;
  @override
  Uint8List argon2(Argon2Arguments args) => Uint8List.fromList(sha256.convert([...args.key, ...args.salt]).bytes);
  @override
  Future<Uint8List> argon2Async(Argon2Arguments args) async => argon2(args);
}

// Uses no dart:io so it runs on the VM, `dart test -p chrome` and `dart test -p chrome --compiler dart2wasm`.
void main() {
  setUpAll(() => KdbxFormat.dartWebWorkaround = true);
  tearDownAll(() => KdbxFormat.dartWebWorkaround = false);

  final attachment = Uint8List.fromList(List.generate(20000, (i) => (i * 13) % 251));

  for (final entry in {
    'KDBX 3 (AES-KDF, gzip)': KdbxHeader.createV3,
    'KDBX 4.1 (Argon2, gzip, binary pool)': KdbxHeader.createV4_1,
  }.entries) {
    test('save and read: ${entry.key}', () async {
      final format = KdbxFormat(null, _FakeArgon2());
      final credentials = Credentials(ProtectedValue.fromString('password'));
      final file = format.create(credentials, 'web test', header: entry.value());
      final kdbxEntry = KdbxEntry.create(file, file.body.rootGroup);
      kdbxEntry.setString(KdbxKeyCommon.TITLE, PlainValue('title'));
      kdbxEntry.setString(KdbxKeyCommon.PASSWORD, ProtectedValue.fromString('secret'));
      kdbxEntry.createBinary(isProtected: true, name: 'a.bin', bytes: attachment);
      file.body.rootGroup.addEntry(kdbxEntry);

      final bytes = await file.save();
      final read = await format.read(bytes, Credentials(ProtectedValue.fromString('password')));
      final readEntry = read.body.rootGroup.entries.values.single;
      expect(readEntry.getString(KdbxKeyCommon.TITLE)!.getText(), 'title');
      expect(readEntry.getString(KdbxKeyCommon.PASSWORD)!.getText(), 'secret');
      expect(readEntry.binaryEntries.single.value.value, attachment);
    });
  }

  test('inline binaries in XML (KDBX 3 style) are compressed and decompressed', () {
    final binary = KdbxBinary(isInline: true, isProtected: false, value: attachment);
    final node = XmlElement(XmlName('Value'));
    binary.saveToXml(node);
    expect(node.getAttribute('Compressed'), 'True');
    final read = KdbxBinary.readBinaryXml(node, isInline: true);
    expect(read.value, attachment);
  });
}
