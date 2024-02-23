import 'package:kdbx/kdbx.dart';
import 'package:kdbx/src/internal/extension_utils.dart';
import 'package:kdbx/src/kdbx_xml.dart';
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
      checkDateValues(v4);
      await TestUtil.saveTestOutput('kdbx4upgrade4-41', v4);
    }, tags: 'kdbx4');

    test('kdbx4.1 is the new default', () async {
      final file =
          format.create(Credentials(ProtectedValue.fromString('asdf')), 'test');
      expect(file.header.version, KdbxVersion.V4_1);
    });

    test('Upgrade from < v4 transforms persisted date format', () async {
      final file =
          await TestUtil.readKdbxFile('test/FooBar.kdbx', password: 'FooBar');
      expect(file.header.version, KdbxVersion.V3_1);
      file.upgrade(KdbxVersion.V4.major, 1);
      final v4 = await TestUtil.saveAndRead(await TestUtil.saveAndRead(file));
      expect(v4.header.version, KdbxVersion.V4_1);
      checkDateValues(v4);
    }, tags: 'kdbx4');

    test('Forced upgrade from v4.1 with bad dates transforms date format',
        () async {
      final file = await TestUtil.readKdbxFile(
          'test/test_files/v4_1-invalid-dates.kdbx',
          password: 'asdf');
      expect(file.header.version, KdbxVersion.V4_1);
      file.upgrade(KdbxVersion.V4.major, 1);
      final v4 = await TestUtil.saveAndRead(await TestUtil.saveAndRead(file));
      expect(v4.header.version, KdbxVersion.V4_1);
      checkDateValues(v4);
    }, tags: 'kdbx4');

    test('Upgrade from v4.0 with good dates', () async {
      final file = await TestUtil.readKdbxFile('test/test_files/v4.0.kdbx',
          password: 'FooBar');
      expect(file.header.version, KdbxVersion.V4);
      file.upgrade(KdbxVersion.V4.major, 1);
      final v4 = await TestUtil.saveAndRead(await TestUtil.saveAndRead(file));
      expect(v4.header.version, KdbxVersion.V4_1);
      checkDateValues(v4);
    }, tags: 'kdbx4');
  }, tags: ['kdbx4']);
}

void checkDateValues(KdbxFile v4) {
  final metaValues = [
    v4.body.meta.node.singleElement('DatabaseNameChanged')?.text,
    v4.body.meta.node.singleElement('DatabaseDescriptionChanged')?.text,
    v4.body.meta.node.singleElement('DefaultUserNameChanged')?.text,
    v4.body.meta.node.singleElement('MasterKeyChanged')?.text,
    v4.body.meta.node.singleElement('RecycleBinChanged')?.text,
    v4.body.meta.node.singleElement('EntryTemplatesGroupChanged')?.text,
    v4.body.meta.node.singleElement('SettingsChanged')?.text,
  ];
  metaValues.forEach(checkIsBase64Date);

  v4.body.rootGroup.getAllEntries().values.forEach(checkObjectHasBase64Dates);
  v4.body.rootGroup.getAllGroups().values.forEach(checkObjectHasBase64Dates);
}

// Sometimes the nodes can contain an XmlNodeList with a single element, rather than directly containing an XmlText node. Bug in XML lib?
// Have to work around by using deprecated text property which works no matter which approach the library decides to take this time.
void checkObjectHasBase64Dates(KdbxObject? obj) {
  if (obj != null) {
    [
      obj.times.node.singleElement('CreationTime')?.text,
      obj.times.node.singleElement('LastModificationTime')?.text,
      obj.times.node.singleElement('LastAccessTime')?.text,
      obj.times.node.singleElement('ExpiryTime')?.text,
      obj.times.node.singleElement('LocationChanged')?.text,
    ].forEach(checkIsBase64Date);

    if (obj is KdbxEntry) {
      obj.history.forEach(checkObjectHasBase64Dates);
    }
  }
}

void checkIsBase64Date(String? val) {
  if (val != null) {
    expect(DateTimeUtils.fromBase64(val), isA<DateTime>());
  }
}
