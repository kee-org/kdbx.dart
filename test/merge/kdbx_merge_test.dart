import 'package:clock/clock.dart';
import 'package:kdbx/kdbx.dart';
import 'package:kdbx/src/utils/print_utils.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import '../internal/test_utils.dart';

final _logger = Logger('kdbx_merge_test');

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

  Future<KdbxFile> createSimpleFile() async {
    final file = TestUtil.createEmptyFile();
    _createEntry(file, file.body.rootGroup, 'test1', 'test1');
    final subGroup =
        file.createGroup(parent: file.body.rootGroup, name: 'Sub Group');
    _createEntry(file, subGroup, 'test2', 'test2');
    proceedSeconds(10);
    return await TestUtil.saveAndRead(file);
  }

  Future<KdbxFile> createRealFile() async {
    final file = TestUtil.createEmptyFile();
    _createEntry(file, file.body.rootGroup, 'test1', 'test1');
    final subGroup =
        file.createGroup(parent: file.body.rootGroup, name: 'Sub Group');
    _createEntry(file, subGroup, 'test2', 'test2');
    file.createGroup(parent: file.body.rootGroup, name: 'Sub Group 2');
    proceedSeconds(10);
    return await TestUtil.saveAndRead(file);
  }

  Future<KdbxFile> createGroupMergeFile() async {
    final file = TestUtil.createEmptyFile();
    _createEntry(file, file.body.rootGroup, 'test1', 'test1');
    final subGroup =
        file.createGroup(parent: file.body.rootGroup, name: 'Sub Group');
    _createEntry(file, subGroup, 'test2', 'test2');
    file.createGroup(parent: file.body.rootGroup, name: 'Sub Group 2');
    file.createGroup(parent: file.body.rootGroup, name: 'target group');
    proceedSeconds(10);
    return await TestUtil.saveAndRead(file);
  }

  Future<KdbxFile> createFileWithHistory() async {
    final file = TestUtil.createEmptyFile();
    final entry = _createEntry(file, file.body.rootGroup, 'test1', 'test1');
    await TestUtil.saveAndRead(file);
    entry.setString(KdbxKeyCommon.USER_NAME, PlainValue('test2'));
    await TestUtil.saveAndRead(file);
    entry.setString(KdbxKeyCommon.USER_NAME, PlainValue('test3'));
    proceedSeconds(10);
    return await TestUtil.saveAndRead(file);
  }

  group('Simple merges', () {
    test('Noop merge', () async {
      final file = await createSimpleFile();
      final file2 = await TestUtil.saveAndRead(file);
      final merge = file.merge(file2);
      final set = Set<KdbxUuid>.from(merge.merged.keys);
      expect(set, hasLength(4));
      expect(merge.changes, isEmpty);
    });
    test('Username change', () async {
      await withClock(fakeClock, () async {
        final file = await createSimpleFile();

        final fileMod = await TestUtil.saveAndRead(file);

        fileMod.body.rootGroup.entries.first
            .setString(KdbxKeyCommon.USER_NAME, PlainValue('changed.'));
        _logger.info('mod date: ' +
            fileMod.body.rootGroup.entries.first.times.lastModificationTime
                .get()
                .toString());
        final file2 = await TestUtil.saveAndRead(fileMod);

        _logger.info('\n\n\nstarting merge.\n');
        final merge = file.merge(file2);
        expect(file.body.rootGroup.entries.first.history, hasLength(1));
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(4));
        expect(merge.changes, hasLength(1));
      });
    });
    test(
      'Change Group Name',
      () async => await withClock(fakeClock, () async {
        final file = await createSimpleFile();

        final fileMod = await TestUtil.saveAndRead(file);

        fileMod.body.rootGroup.groups.first.name.set('Sub Group New Name.');
        final file2 = await TestUtil.saveAndRead(fileMod);
        final merge = file.merge(file2);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(4));
        expect(merge.changes, hasLength(1));
      }),
    );
  });

  group('Real merges', () {
    test('Local file custom data wins', () async {
      await withClock(fakeClock, () async {
        final file = await createRealFile();

        final fileMod = await TestUtil.saveAndRead(file);
        final fileReverse = await TestUtil.saveAndRead(file);

        fileMod.body.meta.customData['custom1'] = 'custom value 2';
        proceedSeconds(10);
        file.body.meta.customData['custom1'] = 'custom value 1';
        fileMod.body.meta.customData['custom2'] = 'custom value 3';

        final file2 = await TestUtil.saveAndRead(fileMod);
        final file2Reverse = await TestUtil.saveAndRead(fileMod);

        final merge = file.merge(file2);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(5));
        expect(file.body.meta.customData['custom1'], 'custom value 1');
        expect(file.body.meta.customData['custom2'], 'custom value 3');

        final mergeReverse = file2Reverse.merge(fileReverse);
        final setReverse = Set<KdbxUuid>.from(mergeReverse.merged.keys);
        expect(setReverse, hasLength(5));
        expect(file2Reverse.body.meta.customData['custom1'], 'custom value 2');
        expect(file2Reverse.body.meta.customData['custom2'], 'custom value 3');
      });
    });

    test('Generates merge error when merging another db', () async {
      final file = await createRealFile();
      final file2 = await createRealFile();
      expect(
        () => file.merge(file2),
        throwsA(
          isA<KdbxUnsupportedException>().having(
            (error) => error.hint,
            'hint',
            'Root groups of source and dest file do not match.',
          ),
        ),
      );
    });
  });

  group('Moving entries', () {
    test(
      'Move entry to existing group in local file',
      () async => await withClock(fakeClock, () async {
        final file = await createRealFile();

        final fileMod = await TestUtil.saveAndRead(file);
        file.move(
            file.body.rootGroup.entries.first, file.body.rootGroup.groups[1]);

        final file2 = await TestUtil.saveAndRead(fileMod);
        final merge = file.merge(file2);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(5));
        expect(file.body.rootGroup.entries.length, 0);
        expect(file.body.rootGroup.groups[1].entries.length, 1);
      }),
    );

    test(
      'Move entry to existing group in remote file',
      () async => await withClock(fakeClock, () async {
        final file = await createRealFile();

        final fileMod = await TestUtil.saveAndRead(file);
        fileMod.move(fileMod.body.rootGroup.entries.first,
            fileMod.body.rootGroup.groups[1]);

        final file2 = await TestUtil.saveAndRead(fileMod);
        final merge = file.merge(file2);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(5));
        expect(file.body.rootGroup.entries.length, 0);
        expect(file.body.rootGroup.groups[1].entries.length, 1);
      }),
    );

    test(
      'Move entry to existing group in both files',
      () async => await withClock(fakeClock, () async {
        final file = await createRealFile();

        final fileMod = await TestUtil.saveAndRead(file);
        file.move(
            file.body.rootGroup.entries.first, file.body.rootGroup.groups[1]);
        fileMod.move(fileMod.body.rootGroup.entries.first,
            fileMod.body.rootGroup.groups[1]);

        final file2 = await TestUtil.saveAndRead(fileMod);
        final merge = file.merge(file2);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(5));
        expect(file.body.rootGroup.entries.length, 0);
        expect(file.body.rootGroup.groups[1].entries.length, 1);
      }),
    );

    test(
      'Move entry to different existing groups in both files',
      () async => await withClock(fakeClock, () async {
        final file = await createRealFile();

        final fileMod = await TestUtil.saveAndRead(file);
        file.move(
            file.body.rootGroup.entries.first, file.body.rootGroup.groups[0]);
        fileMod.move(fileMod.body.rootGroup.entries.first,
            fileMod.body.rootGroup.groups[1]);

        final file2 = await TestUtil.saveAndRead(fileMod);
        final merge = file.merge(file2);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(5));
        expect(file.body.rootGroup.entries.length, 0);
        expect(file.body.rootGroup.groups[0].entries.length, 2);
        expect(file.body.rootGroup.groups[1].entries.length, 0);
      }),
    );

    test(
      'Move entry to new group in local file',
      () async => await withClock(fakeClock, () async {
        final file = await createRealFile();

        final fileMod = await TestUtil.saveAndRead(file);
        final newGroup =
            file.createGroup(parent: file.body.rootGroup, name: 'New group 1');
        file.move(file.body.rootGroup.entries.first, newGroup);

        final file2 = await TestUtil.saveAndRead(fileMod);
        final merge = (await TestUtil.saveAndRead(file)).merge(file2);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(5));
        expect(file.body.rootGroup.entries.length, 0);
        expect(file.body.rootGroup.groups[2].entries.length, 1);
      }),
    );

    test(
      'Move entry to new group in remote file',
      () async => await withClock(fakeClock, () async {
        final file = await createRealFile();

        final fileMod = await TestUtil.saveAndRead(file);
        final newGroup = fileMod.createGroup(
            parent: fileMod.body.rootGroup, name: 'New group 1');
        fileMod.move(fileMod.body.rootGroup.entries.first, newGroup);

        final file2 = await TestUtil.saveAndRead(fileMod);
        final merge = file.merge(file2);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(6));
        expect(file.body.rootGroup.entries.length, 0);
        expect(file.body.rootGroup.groups[2].entries.length, 1);
      }),
    );

    test(
      'Move entry to new group in both files',
      () async => await withClock(fakeClock, () async {
        final file = await createRealFile();

        final fileMod = await TestUtil.saveAndRead(file);
        final newGroup =
            file.createGroup(parent: file.body.rootGroup, name: 'New group 1');
        file.move(file.body.rootGroup.entries.first, newGroup);
        final newGroup2 = fileMod.createGroup(
            parent: fileMod.body.rootGroup, name: 'New group 1');
        fileMod.move(fileMod.body.rootGroup.entries.first, newGroup2);

        final file2 = await TestUtil.saveAndRead(fileMod);
        final merge = file.merge(file2);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(6));
        expect(file.body.rootGroup.entries.length, 0);
        expect(file.body.rootGroup.groups[2].entries.length, 1);
      }),
    );
  });

  group('Recycling and deleting', () {
    test(
      'Move Entry to recycle bin',
      () async => await withClock(fakeClock, () async {
        final file = await createSimpleFile();

        final fileMod = await TestUtil.saveAndRead(file);

        expect(fileMod.recycleBin, isNull);
        fileMod.deleteEntry(fileMod.body.rootGroup.entries.first);
        expect(fileMod.recycleBin, isNotNull);
        final file2 = await TestUtil.saveAndRead(fileMod);
        final merge = file.merge(file2);
        _logger.info('Merged file:\n'
            '${KdbxPrintUtils().catGroupToString(file.body.rootGroup)}');
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(5));
        expect(Set<KdbxNode>.from(merge.changes.map<KdbxNode>((e) => e.object)),
            hasLength(2));
      }),
    );
    test(
      'Move Entry to recycle bin in both files',
      () async => await withClock(fakeClock, () async {
        final file = await createRealFile();

        final fileMod = await TestUtil.saveAndRead(file);

        expect(fileMod.recycleBin, isNull);
        fileMod.deleteEntry(fileMod.body.rootGroup.entries.first);
        expect(fileMod.recycleBin, isNotNull);
        final file2 = await TestUtil.saveAndRead(fileMod);
        file.deleteEntry(file.body.rootGroup.entries.first);
        expect(file.recycleBin, isNotNull);
        final merge = file.merge(file2);
        _logger.info('Merged file:\n'
            '${KdbxPrintUtils().catGroupToString(file.body.rootGroup)}');
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(6));
        expect(Set<KdbxNode>.from(merge.changes.map<KdbxNode>((e) => e.object)),
            hasLength(1));
        expect(file.recycleBin.entries.length, 1);
      }),
    );
    test(
      'Move Entry to recycle bin in original file',
      () async => await withClock(fakeClock, () async {
        final file = await createRealFile();

        final fileMod = await TestUtil.saveAndRead(file);

        expect(fileMod.recycleBin, isNull);
        fileMod.deleteEntry(fileMod.body.rootGroup.entries.first);
        expect(fileMod.recycleBin, isNotNull);
        final file2 = await TestUtil.saveAndRead(fileMod);
        final merge = file2.merge(file);
        _logger.info('Merged file:\n'
            '${KdbxPrintUtils().catGroupToString(file2.body.rootGroup)}');
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(5));
        expect(Set<KdbxNode>.from(merge.changes.map<KdbxNode>((e) => e.object)),
            hasLength(0));
        expect(file2.recycleBin.entries.length, 1);
      }),
    );
    test(
        'Move different entries to new recycle bins in both files results in both in recycle bin',
        () async => await withClock(fakeClock, () async {
              final file = await createRealFile();

              final fileMod = await TestUtil.saveAndRead(file);

              expect(file.recycleBin, isNull);
              file.deleteEntry(file.body.rootGroup.entries.first);
              expect(file.recycleBin, isNotNull);

              expect(fileMod.recycleBin, isNull);
              fileMod.deleteEntry(
                  fileMod.body.rootGroup.groups.first.entries.first);
              expect(fileMod.recycleBin, isNotNull);
              final fileLocal = await TestUtil.saveAndRead(file);
              final fileRemote = await TestUtil.saveAndRead(fileMod);

              final merge = fileLocal.merge(fileRemote);
              _logger.info('Merged file:\n'
                  '${KdbxPrintUtils().catGroupToString(fileLocal.body.rootGroup)}');
              final set = Set<KdbxUuid>.from(merge.merged.keys);
              expect(set, hasLength(6));
              expect(
                  Set<KdbxNode>.from(
                      merge.changes.map<KdbxNode>((e) => e.object)),
                  hasLength(2));
              expect(fileLocal.recycleBin.entries.length, 2);
              expect(fileLocal.body.rootGroup.entries.length, 0);
              expect(fileLocal.body.rootGroup.groups[0].entries.length, 0);
              expect(fileLocal.body.rootGroup.groups[1].entries.length, 0);
            }),
        skip:
            "Merge algorihm can't cope with this so we define the behaviour in the test below instead. Possibly can't ever be improved but it's something to aim for one day. Current behaviour at least ensures no data loss is possible.");
    test(
      'Move different entries to new recycle bins in both files leaves one in the recycle bin and the other in a new group called Trash',
      () async => await withClock(fakeClock, () async {
        final file = await createRealFile();

        final fileMod = await TestUtil.saveAndRead(file);

        expect(file.recycleBin, isNull);
        file.deleteEntry(file.body.rootGroup.entries.first);
        expect(file.recycleBin, isNotNull);

        expect(fileMod.recycleBin, isNull);
        fileMod.deleteEntry(fileMod.body.rootGroup.groups.first.entries.first);
        expect(fileMod.recycleBin, isNotNull);
        final fileLocal = await TestUtil.saveAndRead(file);
        final fileRemote = await TestUtil.saveAndRead(fileMod);

        final merge = fileLocal.merge(fileRemote);
        _logger.info('Merged file:\n'
            '${KdbxPrintUtils().catGroupToString(fileLocal.body.rootGroup)}');
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(6));
        expect(Set<KdbxNode>.from(merge.changes.map<KdbxNode>((e) => e.object)),
            hasLength(2));
        expect(fileLocal.recycleBin.entries.length, 1);
        expect(fileLocal.body.rootGroup.entries.length, 0);
        expect(fileLocal.body.rootGroup.groups[0].entries.length, 0);
        expect(fileLocal.body.rootGroup.groups[1].entries.length, 0);
        expect(fileLocal.body.rootGroup.groups[3].entries.length, 1);
      }),
    );
    test(
      'Adds binary to remote entry',
      () async => await withClock(fakeClock, () async {
        final file = await createRealFile();

        final fileMod = await TestUtil.saveAndRead(file);
      }),
    );
  });

  group('Group merges', () {
    test(
      'Adds new remote group',
      () async => await withClock(fakeClock, () async {
        final file = await createRealFile();

        final fileMod = await TestUtil.saveAndRead(file);
        fileMod.createGroup(
            parent: fileMod.body.rootGroup, name: 'New group 1');

        final file2 = await TestUtil.saveAndRead(fileMod);
        final merge = file.merge(file2);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(6));
        expect(file.body.rootGroup.groups.length, 3);
      }),
    );
    test(
      'Adds new local group',
      () async => await withClock(fakeClock, () async {
        final file = await createRealFile();

        final fileMod = await TestUtil.saveAndRead(file);
        fileMod.createGroup(
            parent: fileMod.body.rootGroup, name: 'New group 1');

        final file2 = await TestUtil.saveAndRead(fileMod);
        final merge = file2.merge(file);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(5));
        expect(file2.body.rootGroup.groups.length, 3);
      }),
    );
    test(
      'Deletes remote group',
      () async => await withClock(fakeClock, () async {
        final file = await createRealFile();

        final fileMod = await TestUtil.saveAndRead(file);
        fileMod.deleteGroup(fileMod.body.rootGroup.groups[1]);

        final file2 = await TestUtil.saveAndRead(fileMod);
        final merge = file.merge(file2);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(6));
        expect(file.body.rootGroup.groups.length, 2);
        expect(file.recycleBin.groups.length, 1);
      }),
    );
    test(
      'Deletes local group',
      () async => await withClock(fakeClock, () async {
        final file = await createRealFile();

        final fileMod = await TestUtil.saveAndRead(file);
        fileMod.deleteGroup(fileMod.body.rootGroup.groups[1]);

        final file2 = await TestUtil.saveAndRead(fileMod);
        final merge = file2.merge(file);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(5));
        expect(file2.body.rootGroup.groups.length, 2);
        expect(file2.recycleBin.groups.length, 1);
      }),
    );
    test(
      'group moved to locally moved group',
      () async => await withClock(fakeClock, () async {
        final fileLocal = await createGroupMergeFile();

        final fileRemote = await TestUtil.saveAndRead(fileLocal);
        fileRemote.move(fileRemote.body.rootGroup.groups[1],
            fileRemote.body.rootGroup.groups[2]);
        fileLocal.move(fileLocal.body.rootGroup.groups[2],
            fileLocal.body.rootGroup.groups[0]);
        final merge = fileLocal.merge(fileRemote);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(6));
        expect(fileLocal.body.rootGroup.groups.length, 1);
        expect(fileLocal.body.rootGroup.groups[0].groups.length, 1);
      }),
    );
    test(
      'group moved to remotely moved group',
      () async => await withClock(fakeClock, () async {
        final fileRemote = await createGroupMergeFile();

        final fileLocal = await TestUtil.saveAndRead(fileRemote);
        fileLocal.move(fileLocal.body.rootGroup.groups[1],
            fileLocal.body.rootGroup.groups[2]);
        fileRemote.move(fileRemote.body.rootGroup.groups[2],
            fileRemote.body.rootGroup.groups[0]);
        final merge = fileLocal.merge(fileRemote);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(6));
        expect(fileLocal.body.rootGroup.groups.length, 1);
        expect(fileLocal.body.rootGroup.groups[0].groups.length, 1);
      }),
    );
  });

// meh?
//  'merges binaries'
//  ('merges custom icons',
  //
  // group('History merges', () {
  //   test(
  //     'deletes all history state remotely',
  //     () async => await withClock(fakeClock, () async {
  //       final fileRemote = await createFileWithHistory();

  //       final fileLocal = await TestUtil.saveAndRead(fileRemote);
  //       fileRemote.body.rootGroup.entries[0].history.clear();
  //       final merge = fileLocal.merge(fileRemote);
  //       final set = Set<KdbxUuid>.from(merge.merged.keys);
  //       expect(set, hasLength(2));
  //       expect(fileLocal.body.rootGroup.entries[0].history.isEmpty, true);
  //       expect(
  //           fileLocal.body.rootGroup.entries[0]
  //               .getString(KdbxKeyCommon.USER_NAME)
  //               .getText(),
  //           'test3');
  //     }),
  //   );
  //   test(
  //     'deletes all history state locally',
  //     () async => await withClock(fakeClock, () async {
  //       final fileRemote = await createFileWithHistory();

  //       final fileLocal = await TestUtil.saveAndRead(fileRemote);
  //       fileLocal.body.rootGroup.entries[0].history.clear();
  //       final merge = fileLocal.merge(fileRemote);
  //       final set = Set<KdbxUuid>.from(merge.merged.keys);
  //       expect(set, hasLength(2));
  //       expect(fileLocal.body.rootGroup.entries[0].history.isEmpty, true);
  //       expect(
  //           fileLocal.body.rootGroup.entries[0]
  //               .getString(KdbxKeyCommon.USER_NAME)
  //               .getText(),
  //           'test3');
  //     }),
  //   );
  //   test(
  //     'deletes single history state remotely',
  //     () async => await withClock(fakeClock, () async {
  //       final fileRemote = await createFileWithHistory();

  //       final fileLocal = await TestUtil.saveAndRead(fileRemote);
  //       fileRemote.body.rootGroup.entries[0].history.removeAt(0);
  //       final merge = fileLocal.merge(fileRemote);
  //       final set = Set<KdbxUuid>.from(merge.merged.keys);
  //       expect(set, hasLength(2));
  //       expect(fileLocal.body.rootGroup.entries[0].history.length, 1);
  //       expect(
  //           fileLocal.body.rootGroup.entries[0]
  //               .getString(KdbxKeyCommon.USER_NAME)
  //               .getText(),
  //           'test3');
  //     }),
  //   );
  //   test(
  //     'deletes single history state locally',
  //     () async => await withClock(fakeClock, () async {
  //       final fileRemote = await createFileWithHistory();

  //       final fileLocal = await TestUtil.saveAndRead(fileRemote);
  //       fileLocal.body.rootGroup.entries[0].history.removeAt(0);
  //       final merge = fileLocal.merge(fileRemote);
  //       final set = Set<KdbxUuid>.from(merge.merged.keys);
  //       expect(set, hasLength(2));
  //       expect(fileLocal.body.rootGroup.entries[0].history.length, 1);
  //       expect(
  //           fileLocal.body.rootGroup.entries[0]
  //               .getString(KdbxKeyCommon.USER_NAME)
  //               .getText(),
  //           'test3');
  //     }),
  //   );
  //   test(
  //     'remote history state from past is pushed to local history stack',
  //     () async => await withClock(fakeClock, () async {
  //       final fileRemote = await createFileWithHistory();

  //       final fileLocal = await TestUtil.saveAndRead(fileRemote);
  //       fileRemote.body.rootGroup.entries[0].history.removeAt(0);
  //       final merge = fileLocal.merge(fileRemote);
  //       final set = Set<KdbxUuid>.from(merge.merged.keys);
  //       expect(set, hasLength(2));
  //       expect(fileLocal.body.rootGroup.entries[0].history.length, 1);
  //       expect(
  //           fileLocal.body.rootGroup.entries[0]
  //               .getString(KdbxKeyCommon.USER_NAME)
  //               .getText(),
  //           'test3');
  //     }),
  //   );
  // });

  // it('adds past history state remotely', function() {
  //     var db = getTestDb(),
  //         remote = getTestDb();
  //     var remoteEntry = remote.getDefaultGroup().entries[0];
  //     var entry = db.getDefaultGroup().entries[0];
  //     remoteEntry.times.lastModTime = dt.upd3;
  //     entry.times.lastModTime = dt.upd4;
  //     remoteEntry.pushHistory();
  //     remoteEntry.times.lastModTime = dt.upd4;
  //     db.merge(remote);
  //     var exp = getTestDbStructure();
  //     exp.root.entries[0].modified = dt.upd4;
  //     exp.root.entries[0].history.push({ modified: dt.upd3, tags: 'tags' });
  //     assertDbEquals(db, exp);
  // });

  // it('adds future history state remotely and converts current state into history', function() {
  //     var db = getTestDb(),
  //         remote = getTestDb();
  //     var remoteEntry = remote.getDefaultGroup().entries[0];
  //     var entry = db.getDefaultGroup().entries[0];
  //     remoteEntry.times.lastModTime = dt.upd4;
  //     remoteEntry.tags = 't4';
  //     remoteEntry.pushHistory();
  //     remoteEntry.times.lastModTime = dt.upd5;
  //     remoteEntry.tags = 'tRemote';
  //     entry.tags = 'tLocal';
  //     db.merge(remote);
  //     var exp = getTestDbStructure();
  //     exp.root.entries[0].modified = dt.upd5;
  //     exp.root.entries[0].tags = 'tRemote';
  //     exp.root.entries[0].history.push({ modified: dt.upd3, tags: 'tLocal' });
  //     exp.root.entries[0].history.push({ modified: dt.upd4, tags: 't4' });
  //     assertDbEquals(db, exp);
  // });

  // it('adds history state locally and converts remote state into history', function() {
  //     var db = getTestDb(),
  //         remote = getTestDb();
  //     var remoteEntry = remote.getDefaultGroup().entries[0];
  //     var entry = db.getDefaultGroup().entries[0];
  //     remoteEntry.times.lastModTime = dt.upd5;
  //     remoteEntry.tags = 'tRemote';
  //     entry.tags = 't4';
  //     entry.times.lastModTime = dt.upd4;
  //     entry.pushHistory();
  //     entry.tags = 'tLocal';
  //     entry.times.lastModTime = dt.upd6;
  //     db.merge(remote);
  //     var exp = getTestDbStructure();
  //     exp.root.entries[0].modified = dt.upd6;
  //     exp.root.entries[0].tags = 'tLocal';
  //     exp.root.entries[0].history.push({ modified: dt.upd4, tags: 't4' });
  //     exp.root.entries[0].history.push({ modified: dt.upd5, tags: 'tRemote' });
  //     assertDbEquals(db, exp);
  // });

  // it('can merge with old entry state without state deletions', function() {
  //     var db = getTestDb(),
  //         remote = getTestDb();
  //     var entry = db.getDefaultGroup().entries[0];
  //     entry.times.lastModTime = dt.upd4;
  //     entry.tags = 't4';
  //     entry.pushHistory();
  //     entry.tags = 'tLocal';
  //     entry.times.lastModTime = dt.upd5;
  //     entry._editState = undefined;
  //     db.merge(remote);
  //     var exp = getTestDbStructure();
  //     exp.root.entries[0].tags = 'tLocal';
  //     exp.root.entries[0].modified = dt.upd5;
  //     exp.root.entries[0].history.push({ modified: dt.upd3, tags: 'tags' });
  //     exp.root.entries[0].history.push({ modified: dt.upd4, tags: 't4' });
  //     assertDbEquals(db, exp);
  // });

  // group('Kdbx4.1 merges', () {
  //   Future<KdbxFile> createRealFile() async {
  //     final file = TestUtil.createEmptyFile();
  //     _createEntry(file, file.body.rootGroup, 'test1', 'test1');
  //     final subGroup =
  //         file.createGroup(parent: file.body.rootGroup, name: 'Sub Group');
  //     _createEntry(file, subGroup, 'test2', 'test2');
  //     proceedSeconds(10);
  //     return await TestUtil.saveAndRead(file);
  //   }

  //   test('Newest file plugin data wins', () async {
  //     await withClock(fakeClock, () async {
  //       final file = await createRealFile();

  //       final fileMod = await TestUtil.saveAndRead(file);
  //     });
  //   });
  // });
}

KdbxEntry _createEntry(
    KdbxFile file, KdbxGroup group, String username, String password) {
  final entry = KdbxEntry.create(file, group);
  group.addEntry(entry);
  entry.setString(KdbxKeyCommon.USER_NAME, PlainValue(username));
  entry.setString(KdbxKeyCommon.PASSWORD, ProtectedValue.fromString(password));
  return entry;
}
