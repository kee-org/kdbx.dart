@Tags(['kdbx3', 'kdbx4'])

import 'package:kdbx/kdbx.dart';
import 'package:test/test.dart';

import 'internal/test_utils.dart';

void main() {
  TestUtil.setupLogging();
  group('Test kdbx format upgrades', () {
    final format = TestUtil.kdbxFormat();
    test('Read v3, write v4', () async {
      final file =
          await TestUtil.readKdbxFile('test/FooBar.kdbx', password: 'FooBar');
      expect(file.header.version, KdbxVersion.V3_1);
      file.upgrade(KdbxVersion.V4.major, 0);
      final v4 = await TestUtil.saveAndRead(file);
      expect(v4.header.version, KdbxVersion.V4);
      await TestUtil.saveTestOutput('kdbx4upgrade3-4', v4);
    }, tags: 'kdbx3');

    test('Read v3, write v4.1', () async {
      final file =
          await TestUtil.readKdbxFile('test/FooBar.kdbx', password: 'FooBar');
      expect(file.header.version, KdbxVersion.V3_1);
      file.upgrade(KdbxVersion.V4.major, 1);
      final v4 = await TestUtil.saveAndRead(file);
      expect(v4.header.version, KdbxVersion.V4_1);
      await TestUtil.saveTestOutput('kdbx4upgrade3-41', v4);
    }, tags: 'kdbx4');

    test('Read v4, write v4.1', () async {
      final file = await TestUtil.readKdbxFile('test/kdbx4_keeweb.kdbx',
          password: 'asdf');
      expect(file.header.version, KdbxVersion.V4);
      file.upgrade(KdbxVersion.V4.major, 1);
      final v4 = await TestUtil.saveAndRead(file);
      expect(v4.header.version, KdbxVersion.V4_1);
      await TestUtil.saveTestOutput('kdbx4upgrade4-41', v4);
    }, tags: 'kdbx4');
    test('kdbx4.1 is the new default', () async {
      final file =
          format.create(Credentials(ProtectedValue.fromString('asdf')), 'test');
      expect(file.header.version, KdbxVersion.V4_1);
    });
  }, tags: ['kdbx4']);
}
