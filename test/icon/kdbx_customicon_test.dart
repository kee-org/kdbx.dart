import 'package:test/test.dart';
import 'package:kdbx/kdbx.dart';

import '../internal/test_utils.dart';

void main() {
  TestUtil.setupLogging();
  test('load custom icons from file', () async {
    final file = await TestUtil.readKdbxFile('test/icon/icontest.kdbx');
    final entry = file.body.rootGroup.entries.first;
    expect(entry.customIcon?.data, isNotNull);
  });

  test('cleanup removes unused custom icon', () async {
    final file = await TestUtil.readKdbxFile('test/icon/icontest.kdbx');
    final entry = file.body.rootGroup.entries.first;
    file.deleteEntry(entry);
    expect(file.body.meta.customIcons.length, 2);
    file.body.cleanup();
    // In recycle bin
    expect(file.body.meta.customIcons.length, 2);
    file.deleteEntry(entry, true);
    file.body.cleanup();
    // actually deleted
    expect(file.body.meta.customIcons.length, 1);
  });
}
