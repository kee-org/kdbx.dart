import 'package:kdbx/kdbx.dart';
import 'package:kdbx/src/kdbx_xml.dart';
import 'package:test/test.dart';

// Uses no dart:io so it runs on the VM, `dart test -p chrome` and `dart test -p chrome --compiler dart2wasm`.
void main() {
  test('64 bit values survive the web helpers', () {
    KdbxFormat.dartWebWorkaround = true;
    addTearDown(() => KdbxFormat.dartWebWorkaround = false);
    final when = DateTime.utc(2026, 11, 3, 12, 30, 15);
    expect(DateTimeUtils.fromBase64(DateTimeUtils.toBase64(when)), when);
    // and the bytes are what other programs write
    expect(DateTimeUtils.toBase64(DateTime.utc(2026, 11, 3)), 'ABt74g4AAAA=');
  });
}
