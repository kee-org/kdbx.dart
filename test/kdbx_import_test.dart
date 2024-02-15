import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:kdbx/kdbx.dart';
import 'package:test/test.dart';

import 'internal/test_utils.dart';
import 'kdbx_binaries_test.dart';

void main() {
  TestUtil.setupLogging();
  var now = DateTime.fromMillisecondsSinceEpoch(0);

  final fakeClock = Clock(() => now);
  void proceedSeconds(int seconds) {
    now = now.add(Duration(seconds: seconds));
  }

  setUp(() {
    now = DateTime.fromMillisecondsSinceEpoch(0);
  });

  group('Simple imports', () {
    test(
      'Noop import',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createSimpleFile(proceedSeconds);
        final file2 = TestUtil.createEmptyFile();

        file.import(file2);
        expect(file.body.rootGroup.getAllEntries(), hasLength(2));
        expect(file.body.rootGroup.getAllGroups(), hasLength(3));
      }),
    );
    test(
      'Simple import',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createSimpleFile(proceedSeconds);
        final file2 = await TestUtil.createSimpleFile(proceedSeconds);

        file.import(file2);
        expect(file.body.rootGroup.getAllEntries(), hasLength(4));
        expect(file.body.rootGroup.getAllGroups(), hasLength(4));
      }),
    );
    test(
      'Simple import v3.1',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createSimpleFile(proceedSeconds);
        final file2 = await TestUtil.createSimpleFileV3(proceedSeconds);

        file.import(file2);
        expect(file.body.rootGroup.getAllEntries(), hasLength(4));
        expect(file.body.rootGroup.getAllGroups(), hasLength(4));
      }),
    );
    test(
      'Simple import v4 with Argon2id',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createSimpleFile(proceedSeconds);
        final file2 = await TestUtil.createSimpleFileV4Argon2Id(proceedSeconds);

        file.import(file2);
        expect(file.body.rootGroup.getAllEntries(), hasLength(4));
        expect(file.body.rootGroup.getAllGroups(), hasLength(4));
      }),
      skip:
          'Underlying argon ffi library does not produce correct results for 2id hashes (at least in Linux and Android)',
    );
    test(
      'Imports entries with history correctly',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createSimpleFile(proceedSeconds);
        final file2 = await TestUtil.createFileWithHistory(proceedSeconds);
        final sourceEntry = file2.body.rootGroup.entries.values.elementAt(0);
        file.import(file2);
        final importedGroup = file.body.rootGroup.groups.values.elementAt(1);
        final importedEntry = importedGroup.entries.values.elementAt(0);
        expect(file.body.rootGroup.getAllEntries(), hasLength(3));
        expect(file.body.rootGroup.getAllGroups(), hasLength(3));
        expect(importedEntry.getString(KdbxKeyCommon.USER_NAME)?.getText(),
            'test3');
        expect(importedEntry.uuid, isNot(equals(sourceEntry.uuid)));
      }),
    );

    test(
      'Imports entry in bin correctly',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createSimpleFile(proceedSeconds);
        final file2 =
            await TestUtil.createFileWithRecycledEntry(proceedSeconds);
        file.import(file2);
        final importedGroup = file.body.rootGroup.groups.values.elementAt(1);
        final importedBinGroup = file.body.rootGroup
            .getAllGroups()
            .values
            .firstWhere((g) => g.name.get() == 'Imported bin');
        expect(importedGroup.entries.values.isEmpty, isTrue);
        expect(importedBinGroup.entries, hasLength(1));
        expect(file.body.rootGroup.getAllEntries(), hasLength(4));
        expect(file.body.rootGroup.getAllGroups(),
            hasLength(5)); // Includes "Imported bin"
      }),
    );

    test(
      'when entry with a binary is imported, results in file with that binary included in the header',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createRealFile(proceedSeconds);
        final file2 = await TestUtil.createRealFileWithBinary(proceedSeconds);
        expect(file.ctx.binariesIterable.length, 0);
        file.import(file2);
        final importedGroup = file.body.rootGroup.groups.values.last;
        final importedEntry = importedGroup.entries.values.last;
        expect(file.ctx.binariesIterable.length, 1);
        expect(file.body.rootGroup.getAllEntries(), hasLength(5));
        expect(file.ctx.binariesIterable.first.value,
            Uint8List.fromList([1, 2, 3]));
        expectBinary(importedEntry, 'testBin1', hasLength(3));
      }),
    );
  });
}
