// ignore_for_file: invalid_use_of_protected_member

import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:kdbx/kdbx.dart';
import 'package:kdbx/src/utils/print_utils.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import '../internal/test_utils.dart';
import '../kdbx_binaries_test.dart';

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

  group('Simple merges', () {
    test('Noop merge', () async {
      final file = await TestUtil.createSimpleFile(proceedSeconds);
      final file2 = await TestUtil.saveAndRead(file);
      final merge = file.merge(file2);
      final set = Set<KdbxUuid>.from(merge.merged.keys);
      expect(set, hasLength(4));
      expect(merge.changes, isEmpty);
    });
    test('Username change', () async {
      await withClock(fakeClock, () async {
        final file = await TestUtil.createSimpleFile(proceedSeconds);

        final fileMod = await TestUtil.saveAndRead(file);

        fileMod.body.rootGroup.entries.first
            .setString(KdbxKeyCommon.USER_NAME, PlainValue('changed.'));
        _logger.info(
            'mod date: ${fileMod.body.rootGroup.entries.first.times.lastModificationTime.get()}');
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
        final file = await TestUtil.createSimpleFile(proceedSeconds);

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

//TODO: https://github.com/authpass/authpass/issues/335

  group('Real merges', () {
    test('Local file custom data wins', () async {
      await withClock(fakeClock, () async {
        final file = await TestUtil.createRealFile(proceedSeconds);

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

    test('Local entry custom data wins', () async {
      await withClock(fakeClock, () async {
        final file = await TestUtil.createRealFile(proceedSeconds);

        final fileMod = await TestUtil.saveAndRead(file);
        final fileReverse = await TestUtil.saveAndRead(file);

//TODO: check setcustomdata is really needed
        fileMod.body.rootGroup.entries.first
            .setCustomData('custom1', 'custom value 2');
        proceedSeconds(10);
        file.body.rootGroup.entries.first
            .setCustomData('custom1', 'custom value 1');
        fileMod.body.rootGroup.entries.first
            .setCustomData('custom2', 'custom value 3');

        // final fileSavedAndHopefullyDateUpdated =
        //     await TestUtil.saveAndRead(file);
        final file2 = await TestUtil.saveAndRead(fileMod);
        final file2Reverse = await TestUtil.saveAndRead(fileMod);

        final merge = file.merge(file2);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(5));
        expect(file.body.rootGroup.entries.first.customData['custom1'],
            'custom value 1');
        expect(file.body.rootGroup.entries.first.customData['custom2'], null);

        final mergeReverse = file2Reverse.merge(fileReverse);
        final setReverse = Set<KdbxUuid>.from(mergeReverse.merged.keys);
        expect(setReverse, hasLength(5));
        expect(file2Reverse.body.rootGroup.entries.first.customData['custom1'],
            'custom value 2');
        expect(file2Reverse.body.rootGroup.entries.first.customData['custom2'],
            'custom value 3');
      });
    });

    test('Newer entry custom data wins', () async {
      await withClock(fakeClock, () async {
        final file = await TestUtil.createRealFile(proceedSeconds);

        final fileMod = await TestUtil.saveAndRead(file);
        final fileReverse = await TestUtil.saveAndRead(file);

//TODO: check setcustomdata is really needed

        file.body.rootGroup.entries.first
            .setCustomData('custom1', 'custom value 1');
        proceedSeconds(10);
        fileMod.body.rootGroup.entries.first
            .setCustomData('custom1', 'custom value 2');
        fileMod.body.rootGroup.entries.first
            .setCustomData('custom2', 'custom value 3');

        // final fileSavedAndHopefullyDateUpdated =
        //     await TestUtil.saveAndRead(file);
        final file2 = await TestUtil.saveAndRead(fileMod);
        final file2Reverse = await TestUtil.saveAndRead(fileMod);

        final merge = file.merge(file2);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(5));
        expect(file.body.rootGroup.entries.first.customData['custom1'],
            'custom value 2');
        expect(file.body.rootGroup.entries.first.customData['custom2'],
            'custom value 3');

        final mergeReverse = file2Reverse.merge(fileReverse);
        final setReverse = Set<KdbxUuid>.from(mergeReverse.merged.keys);
        expect(setReverse, hasLength(5));
        expect(file2Reverse.body.rootGroup.entries.first.customData['custom1'],
            'custom value 2');
        expect(file2Reverse.body.rootGroup.entries.first.customData['custom2'],
            'custom value 3');
      });
    });

    test('Generates merge error when merging another db', () async {
      final file = await TestUtil.createRealFile(proceedSeconds);
      final file2 = await TestUtil.createRealFile(proceedSeconds);
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
        final file = await TestUtil.createRealFile(proceedSeconds);

        final fileMod = await TestUtil.saveAndRead(file);
        file.move(file.body.rootGroup.entries.first,
            file.body.rootGroup.groups.values.toList()[1]);

        final file2 = await TestUtil.saveAndRead(fileMod);
        final merge = file.merge(file2);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(5));
        expect(file.body.rootGroup.entries.length, 0);
        expect(file.body.rootGroup.groups.values.toList()[1].entries.length, 1);
      }),
    );

    test(
      'Move entry to existing group in remote file',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createRealFile(proceedSeconds);

        final fileMod = await TestUtil.saveAndRead(file);
        fileMod.move(fileMod.body.rootGroup.entries.first,
            fileMod.body.rootGroup.groups.values.toList()[1]);

        final file2 = await TestUtil.saveAndRead(fileMod);
        final merge = file.merge(file2);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(5));
        expect(file.body.rootGroup.entries.length, 0);
        expect(file.body.rootGroup.groups.values.toList()[1].entries.length, 1);
      }),
    );

    test(
      'Move entry to existing group in both files',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createRealFile(proceedSeconds);

        final fileMod = await TestUtil.saveAndRead(file);
        file.move(file.body.rootGroup.entries.first,
            file.body.rootGroup.groups.values.toList()[1]);
        fileMod.move(fileMod.body.rootGroup.entries.first,
            fileMod.body.rootGroup.groups.values.toList()[1]);

        final file2 = await TestUtil.saveAndRead(fileMod);
        final merge = file.merge(file2);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(5));
        expect(file.body.rootGroup.entries.length, 0);
        expect(file.body.rootGroup.groups.values.toList()[1].entries.length, 1);
      }),
    );

    test(
      'Move entry to different existing groups in both files',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createRealFile(proceedSeconds);

        final fileMod = await TestUtil.saveAndRead(file);
        file.move(file.body.rootGroup.entries.first,
            file.body.rootGroup.groups.values.toList()[0]);
        fileMod.move(fileMod.body.rootGroup.entries.first,
            fileMod.body.rootGroup.groups.values.toList()[1]);

        final file2 = await TestUtil.saveAndRead(fileMod);
        final merge = file.merge(file2);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(5));
        expect(file.body.rootGroup.entries.length, 0);
        expect(file.body.rootGroup.groups.values.toList()[0].entries.length, 2);
        expect(file.body.rootGroup.groups.values.toList()[1].entries.length, 0);
      }),
    );

    test(
      'Move entry to new group in local file',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createRealFile(proceedSeconds);

        final fileMod = await TestUtil.saveAndRead(file);
        final newGroup =
            file.createGroup(parent: file.body.rootGroup, name: 'New group 1');
        file.move(file.body.rootGroup.entries.first, newGroup);

        final file2 = await TestUtil.saveAndRead(fileMod);
        final merge = (await TestUtil.saveAndRead(file)).merge(file2);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(5));
        expect(file.body.rootGroup.entries.length, 0);
        expect(file.body.rootGroup.groups.values.toList()[2].entries.length, 1);
      }),
    );

    test(
      'Move entry to new group in remote file',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createRealFile(proceedSeconds);

        final fileMod = await TestUtil.saveAndRead(file);
        final newGroup = fileMod.createGroup(
            parent: fileMod.body.rootGroup, name: 'New group 1');
        fileMod.move(fileMod.body.rootGroup.entries.first, newGroup);

        final file2 = await TestUtil.saveAndRead(fileMod);
        final merge = file.merge(file2);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(6));
        expect(file.body.rootGroup.entries.length, 0);
        expect(file.body.rootGroup.groups.values.toList()[2].entries.length, 1);
      }),
    );

    test(
      'Move entry to new group in both files',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createRealFile(proceedSeconds);

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
        expect(file.body.rootGroup.groups.values.toList()[2].entries.length, 1);
      }),
    );
  });

  group('Recycling and deleting', () {
    test(
      'Move Entry to recycle bin',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createSimpleFile(proceedSeconds);

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
        expect(
            Set<KdbxNode>.from(merge.changes.map<KdbxNode?>((e) => e.object)),
            hasLength(2));
      }),
    );
    test(
      'Move Entry to recycle bin in both files',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createRealFile(proceedSeconds);

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
        expect(
            Set<KdbxNode>.from(merge.changes.map<KdbxNode?>((e) => e.object)),
            hasLength(1));
        expect(file.recycleBin!.entries.length, 1);
      }),
    );
    test(
      'Move Entry to recycle bin in original file',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createRealFile(proceedSeconds);

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
        expect(
            Set<KdbxNode>.from(merge.changes.map<KdbxNode?>((e) => e.object)),
            hasLength(0));
        expect(file2.recycleBin!.entries.length, 1);
      }),
    );
    test(
      'Move different entries to new recycle bins in both files results in both in recycle bin',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createRealFile(proceedSeconds);

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
        expect(
            Set<KdbxNode>.from(merge.changes.map<KdbxNode?>((e) => e.object)),
            hasLength(2));
        expect(fileLocal.recycleBin!.entries.length, 2);
        expect(fileLocal.body.rootGroup.entries.length, 0);
        expect(
            fileLocal.body.rootGroup.groups.values.toList()[0].entries.length,
            0);
        expect(
            fileLocal.body.rootGroup.groups.values.toList()[1].entries.length,
            0);
      }),
      skip:
          "Merge algorihm can't cope with this so we define the behaviour in the test below instead. Possibly can't ever be improved but it's something to aim for one day. Current behaviour at least ensures no data loss is possible.",
    );
    test(
      'Move different entries to new recycle bins in both files leaves one in the recycle bin and the other in a new group called Trash',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createRealFile(proceedSeconds);

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
        expect(
            Set<KdbxNode>.from(merge.changes.map<KdbxNode?>((e) => e.object)),
            hasLength(2));
        expect(fileLocal.recycleBin!.entries.length, 1);
        expect(fileLocal.body.rootGroup.entries.length, 0);
        expect(
            fileLocal.body.rootGroup.groups.values.toList()[0].entries.length,
            0);
        expect(
            fileLocal.body.rootGroup.groups.values.toList()[1].entries.length,
            0);
        expect(
            fileLocal.body.rootGroup.groups.values.toList()[3].entries.length,
            1);
      }),
    );

    test(
      'Delete entry remotely also removes locally',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createSimpleFile(proceedSeconds);

        final fileMod = await TestUtil.saveAndRead(file);
        final removedUuid = fileMod.body.rootGroup.entries.first.uuid.uuid;

        expect(fileMod.recycleBin, isNull);
        fileMod.deleteEntry(fileMod.body.rootGroup.entries.first, true);
        expect(fileMod.recycleBin, isNull);
        final file2 = await TestUtil.saveAndRead(fileMod);
        final merge = file.merge(file2);
        _logger.info('Merged file:\n'
            '${KdbxPrintUtils().catGroupToString(file.body.rootGroup)}');
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        final wasRemoved =
            !file.body.rootGroup.getAllEntries().keys.contains(removedUuid);
        expect(wasRemoved, true);
        expect(set, hasLength(3));
        expect(
            Set<KdbxNode>.from(merge.changes.map<KdbxNode?>((e) => e.object)),
            hasLength(1));
      }),
    );

    test(
      'Delete entry locally is not resurrected',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createSimpleFile(proceedSeconds);

        final removedUuid = file.body.rootGroup.entries.first.uuid.uuid;
        final file2 = await TestUtil.saveAndRead(file);

        file.deleteEntry(file.body.rootGroup.entries.first, true);
        expect(file.recycleBin, isNull);
        final merge = file.merge(file2);
        _logger.info('Merged file:\n'
            '${KdbxPrintUtils().catGroupToString(file.body.rootGroup)}');
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        final isStillRemoved =
            !file.body.rootGroup.getAllEntries().keys.contains(removedUuid);
        expect(isStillRemoved, true);
        expect(set, hasLength(3));
        expect(
            Set<KdbxNode>.from(merge.changes.map<KdbxNode?>((e) => e.object)),
            hasLength(0));
      }),
    );

    test(
      'Delete entry both locally and remotely does not resurrect entry',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createSimpleFile(proceedSeconds);

        final fileMod = await TestUtil.saveAndRead(file);
        final removedUuid = fileMod.body.rootGroup.entries.first.uuid.uuid;

        file.deleteEntry(file.body.rootGroup.entries.first, true);
        fileMod.deleteEntry(fileMod.body.rootGroup.entries.first, true);
        expect(file.recycleBin, isNull);
        expect(fileMod.recycleBin, isNull);
        final file2 = await TestUtil.saveAndRead(fileMod);
        final merge = file.merge(file2);
        _logger.info('Merged file:\n'
            '${KdbxPrintUtils().catGroupToString(file.body.rootGroup)}');
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        final isStillRemoved =
            !file.body.rootGroup.getAllEntries().keys.contains(removedUuid);
        expect(isStillRemoved, true);
        expect(set, hasLength(3));
        expect(
            Set<KdbxNode>.from(merge.changes.map<KdbxNode?>((e) => e.object)),
            hasLength(0));
      }),
    );
    // test(
    //   'Adds binary to remote entry',
    //   () async => await withClock(fakeClock, () async {
    //     final file = await TestUtil.createRealFile(proceedSeconds);
    //     await TestUtil.saveAndRead(file);
    //   }),
    // );
  });

  group('Group merges', () {
    test(
      'Adds new remote group',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createRealFile(proceedSeconds);

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
        final file = await TestUtil.createRealFile(proceedSeconds);

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
        final file = await TestUtil.createRealFile(proceedSeconds);

        final fileMod = await TestUtil.saveAndRead(file);
        fileMod.deleteGroup(fileMod.body.rootGroup.groups.values.toList()[1]);

        final file2 = await TestUtil.saveAndRead(fileMod);
        final merge = file.merge(file2);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(6));
        expect(file.body.rootGroup.groups.length, 2);
        expect(file.recycleBin!.groups.length, 1);
      }),
    );
    test(
      'Deletes local group',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createRealFile(proceedSeconds);

        final fileMod = await TestUtil.saveAndRead(file);
        fileMod.deleteGroup(fileMod.body.rootGroup.groups.values.toList()[1]);

        final file2 = await TestUtil.saveAndRead(fileMod);
        final merge = file2.merge(file);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(5));
        expect(file2.body.rootGroup.groups.length, 2);
        expect(file2.recycleBin!.groups.length, 1);
      }),
    );
    test(
      'group moved to locally moved group',
      () async => await withClock(fakeClock, () async {
        final fileLocal = await TestUtil.createGroupMergeFile(proceedSeconds);

        final fileRemote = await TestUtil.saveAndRead(fileLocal);
        fileRemote.move(fileRemote.body.rootGroup.groups.values.toList()[1],
            fileRemote.body.rootGroup.groups.values.toList()[2]);
        fileLocal.move(fileLocal.body.rootGroup.groups.values.toList()[2],
            fileLocal.body.rootGroup.groups.values.toList()[0]);
        final merge = fileLocal.merge(fileRemote);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(6));
        expect(fileLocal.body.rootGroup.groups.length, 1);
        expect(fileLocal.body.rootGroup.groups.values.toList()[0].groups.length,
            1);
      }),
    );
    test(
      'group moved to remotely moved group',
      () async => await withClock(fakeClock, () async {
        final fileRemote = await TestUtil.createGroupMergeFile(proceedSeconds);

        final fileLocal = await TestUtil.saveAndRead(fileRemote);
        fileLocal.move(fileLocal.body.rootGroup.groups.values.toList()[1],
            fileLocal.body.rootGroup.groups.values.toList()[2]);
        fileRemote.move(fileRemote.body.rootGroup.groups.values.toList()[2],
            fileRemote.body.rootGroup.groups.values.toList()[0]);
        final merge = fileLocal.merge(fileRemote);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(6));
        expect(fileLocal.body.rootGroup.groups.length, 1);
        expect(fileLocal.body.rootGroup.groups.values.toList()[0].groups.length,
            1);
      }),
    );
  });

// meh?
//  'merges binaries'
  //('merges custom icons',

  group('History merges', () {
/*

Idea to improve history merge algorithm in future:

customdata["history_cleared_until"] = seconds since epoch;

set that to "now" whenever user clears history;
in future, allow user to set to an arbitrary point in time;

deleting a specific history entry must be done on every device (probably while offline).

in the short term, that is acceptable for operations of deleting all history and back to a specific point in time.

when merging, can look at this value to decide whether history entries from the other entry should be merged in or not. If missing, assume all history entries from other DB need to be retained.

*/

    // test(
    //   'deletes all history state remotely',
    //   () async => await withClock(fakeClock, () async {
    //     final fileRemote = await TestUtil.createFileWithHistory(proceedSeconds);
    //     final fileLocal = await TestUtil.saveAndRead(fileRemote);
    //     proceedSeconds(10);
    //     fileRemote.body.rootGroup.entries.values.toList()[0].history.clear();
    //     final merge = fileLocal.merge(fileRemote);
    //     final set = Set<KdbxUuid>.from(merge.merged.keys);
    //     expect(set, hasLength(2));
    //     expect(
    //         fileLocal.body.rootGroup.entries.values.toList()[0].history.isEmpty,
    //         true);
    //     expect(
    //         fileLocal.body.rootGroup.entries.values
    //             .toList()[0]
    //             .getString(KdbxKeyCommon.USER_NAME)
    //             .getText(),
    //         'test3');
    //   }),
    // );
    // test(
    //   'deletes all history state locally',
    //   () async => await withClock(fakeClock, () async {
    //     final fileRemote = await TestUtil.createFileWithHistory(proceedSeconds);
    //     final fileLocal = await TestUtil.saveAndRead(fileRemote);
    //     proceedSeconds(10);
    //     fileLocal.body.rootGroup.entries.values.toList()[0].history.clear();
    //     final merge = fileLocal.merge(fileRemote);
    //     final set = Set<KdbxUuid>.from(merge.merged.keys);
    //     expect(set, hasLength(2));
    //     expect(
    //         fileLocal.body.rootGroup.entries.values.toList()[0].history.isEmpty,
    //         true);
    //     expect(
    //         fileLocal.body.rootGroup.entries.values
    //             .toList()[0]
    //             .getString(KdbxKeyCommon.USER_NAME)
    //             .getText(),
    //         'test3');
    //   }),
    // );
    // test(
    //   'deletes single history state remotely',
    //   () async => await withClock(fakeClock, () async {
    //     final fileRemote = await TestUtil.createFileWithHistory(proceedSeconds);
    //     final fileLocal = await TestUtil.saveAndRead(fileRemote);
    //     proceedSeconds(10);
    //     fileRemote.body.rootGroup.entries.values
    //         .toList()[0]
    //         .history
    //         .removeAt(0);
    //     final merge = fileLocal.merge(fileRemote);
    //     final set = Set<KdbxUuid>.from(merge.merged.keys);
    //     expect(set, hasLength(2));
    //     expect(
    //         fileLocal.body.rootGroup.entries.values.toList()[0].history.length,
    //         1);
    //     expect(
    //         fileLocal.body.rootGroup.entries.values
    //             .toList()[0]
    //             .getString(KdbxKeyCommon.USER_NAME)
    //             .getText(),
    //         'test3');
    //   }),
    // );
    // test(
    //   'deletes single history state locally',
    //   () async => await withClock(fakeClock, () async {
    //     final fileRemote = await TestUtil.createFileWithHistory(proceedSeconds);
    //     final fileLocal = await TestUtil.saveAndRead(fileRemote);
    //     proceedSeconds(10);
    //     fileLocal.body.rootGroup.entries.values.toList()[0].history.removeAt(0);
    //     final merge = fileLocal.merge(fileRemote);
    //     final set = Set<KdbxUuid>.from(merge.merged.keys);
    //     expect(set, hasLength(2));
    //     expect(
    //         fileLocal.body.rootGroup.entries.values.toList()[0].history.length,
    //         1);
    //     expect(
    //         fileLocal.body.rootGroup.entries.values
    //             .toList()[0]
    //             .getString(KdbxKeyCommon.USER_NAME)
    //             .getText(),
    //         'test3');
    //   }),
    // );

    test(
      'deletes all history state locally and remotely',
      () async => await withClock(fakeClock, () async {
        final fileRemote = await TestUtil.createFileWithHistory(proceedSeconds);
        final fileLocal = await TestUtil.saveAndRead(fileRemote);
        proceedSeconds(10);
        fileLocal.body.rootGroup.entries.values.toList()[0].history.clear();
        proceedSeconds(10);
        fileRemote.body.rootGroup.entries.values.toList()[0].history.clear();
        final merge = fileLocal.merge(fileRemote);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(2));
        expect(
            fileLocal.body.rootGroup.entries.values.toList()[0].history.isEmpty,
            true);
        expect(
            fileLocal.body.rootGroup.entries.values
                .toList()[0]
                .getString(KdbxKeyCommon.USER_NAME)!
                .getText(),
            'test3');
      }),
    );

    test(
      'deletes single history state locally and remotely',
      () async => await withClock(fakeClock, () async {
        final fileRemote = await TestUtil.createFileWithHistory(proceedSeconds);
        final fileLocal = await TestUtil.saveAndRead(fileRemote);
        proceedSeconds(10);
        fileLocal.body.rootGroup.entries.values.toList()[0].history.removeAt(0);
        proceedSeconds(10);
        fileRemote.body.rootGroup.entries.values
            .toList()[0]
            .history
            .removeAt(0);
        final merge = fileLocal.merge(fileRemote);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(2));
        expect(
            fileLocal.body.rootGroup.entries.values.toList()[0].history.length,
            1);
        expect(
            fileLocal.body.rootGroup.entries.values
                .toList()[0]
                .getString(KdbxKeyCommon.USER_NAME)!
                .getText(),
            'test3');
      }),
    );
    test(
      'remote history state from past is pushed to local history stack',
      () async => await withClock(fakeClock, () async {
        final expectedHistoryTime = fakeClock.now().toUtc();
        final fileSource = await TestUtil.createSimpleFile(proceedSeconds);
        final fileLocal = await TestUtil.saveAndRead(fileSource);
        proceedSeconds(10);
        final expectedEntryTime = fakeClock.now().toUtc();

        fileSource.body.rootGroup.entries.values
            .toList()[0]
            .setString(KdbxKeyCommon.USER_NAME, PlainValue('test2'));
        final fileRemote = await TestUtil.saveAndRead(fileSource);
        proceedSeconds(10);

        final merge = fileLocal.merge(fileRemote);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        final testEntry = fileLocal.body.rootGroup.entries.values.toList()[0];
        expect(set, hasLength(4));
        expect(testEntry.history.length, 1);
        expect(
            testEntry.getString(KdbxKeyCommon.USER_NAME)!.getText(), 'test2');
        expect(testEntry.times.lastModificationTime.get()!.toUtc(),
            expectedEntryTime);
        expect(testEntry.history[0].times.lastModificationTime.get()!.toUtc(),
            expectedHistoryTime);
      }),
    );

    test(
      'new local history state is retained',
      () async => await withClock(fakeClock, () async {
        final expectedHistoryTime = fakeClock.now().toUtc();
        final fileSource = await TestUtil.createSimpleFile(proceedSeconds);
        final fileRemote = await TestUtil.saveAndRead(fileSource);

        proceedSeconds(10);
        final expectedEntryTime = fakeClock.now().toUtc();

        fileSource.body.rootGroup.entries.values
            .toList()[0]
            .setString(KdbxKeyCommon.USER_NAME, PlainValue('test2'));
        final fileLocal = await TestUtil.saveAndRead(fileSource);

        final merge = fileLocal.merge(fileRemote);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        final testEntry = fileLocal.body.rootGroup.entries.values.toList()[0];
        expect(set, hasLength(4));
        expect(testEntry.history.length, 1);
        expect(
            testEntry.getString(KdbxKeyCommon.USER_NAME)!.getText(), 'test2');
        expect(testEntry.times.lastModificationTime.get()!.toUtc(),
            expectedEntryTime);
        expect(testEntry.history[0].times.lastModificationTime.get()!.toUtc(),
            expectedHistoryTime);
      }),
    );

    test(
      'when modified locally then remotely, remote becomes latest; local state is included in combined history states from both',
      () async => await withClock(fakeClock, () async {
        final fileSource = await TestUtil.createFileWithHistory(proceedSeconds);
        final fileSource2 = await TestUtil.saveAndRead(fileSource);

        fileSource.body.rootGroup.entries.values
            .toList()[0]
            .setString(KdbxKeyCommon.USER_NAME, PlainValue('test4local'));
        await TestUtil.saveAndRead(fileSource);
        proceedSeconds(10);
        fileSource.body.rootGroup.entries.values
            .toList()[0]
            .setString(KdbxKeyCommon.USER_NAME, PlainValue('test5local'));
        final fileLocal = await TestUtil.saveAndRead(fileSource);

        proceedSeconds(10);

        fileSource2.body.rootGroup.entries.values
            .toList()[0]
            .setString(KdbxKeyCommon.USER_NAME, PlainValue('test4remote'));
        await TestUtil.saveAndRead(fileSource2);
        proceedSeconds(10);
        fileSource2.body.rootGroup.entries.values
            .toList()[0]
            .setString(KdbxKeyCommon.USER_NAME, PlainValue('test5remote'));
        final fileRemote = await TestUtil.saveAndRead(fileSource2);

        final merge = fileLocal.merge(fileRemote);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(2));
        expect(
            fileLocal.body.rootGroup.entries.values
                .toList()[0]
                .history
                .map((e) => e.getString(KdbxKeyCommon.USER_NAME)!.getText())
                .toList(),
            [
              'test1',
              'test2',
              'test3',
              'test4local',
              'test5local',
              'test4remote'
            ]);
        expect(
            fileLocal.body.rootGroup.entries.values
                .toList()[0]
                .getString(KdbxKeyCommon.USER_NAME)!
                .getText(),
            'test5remote');
      }),
    );

    test(
      'when modified remotely then locally, local remains latest; remote state is included in combined history states from both',
      () async => await withClock(fakeClock, () async {
        final fileSource = await TestUtil.createFileWithHistory(proceedSeconds);
        final fileSource2 = await TestUtil.saveAndRead(fileSource);

        fileSource2.body.rootGroup.entries.values
            .toList()[0]
            .setString(KdbxKeyCommon.USER_NAME, PlainValue('test4remote'));
        await TestUtil.saveAndRead(fileSource2);
        proceedSeconds(10);
        fileSource2.body.rootGroup.entries.values
            .toList()[0]
            .setString(KdbxKeyCommon.USER_NAME, PlainValue('test5remote'));
        final fileRemote = await TestUtil.saveAndRead(fileSource2);

        proceedSeconds(10);

        fileSource.body.rootGroup.entries.values
            .toList()[0]
            .setString(KdbxKeyCommon.USER_NAME, PlainValue('test4local'));
        await TestUtil.saveAndRead(fileSource);
        proceedSeconds(10);
        fileSource.body.rootGroup.entries.values
            .toList()[0]
            .setString(KdbxKeyCommon.USER_NAME, PlainValue('test5local'));
        final fileLocal = await TestUtil.saveAndRead(fileSource);

        final merge = fileLocal.merge(fileRemote);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(2));
        expect(
            fileLocal.body.rootGroup.entries.values
                .toList()[0]
                .history
                .map((e) => e.getString(KdbxKeyCommon.USER_NAME)!.getText())
                .toList(),
            [
              'test1',
              'test2',
              'test3',
              'test4remote',
              'test5remote',
              'test4local'
            ]);
        expect(
            fileLocal.body.rootGroup.entries.values
                .toList()[0]
                .getString(KdbxKeyCommon.USER_NAME)!
                .getText(),
            'test5local');
      }),
    );

// In the real world if user has significantly mismatched times on each device, the kdbx format does not allow us to guarantee correct ordering, or even reliable storage of, individual history entry items. To do so, each history entry would need to be assigned a UUID and thus treated as a primary resource in its own right.
    test(
      'when modified alternatly locally then remotely, remote becomes latest; local state is appended to combined history states from both',
      () async => await withClock(fakeClock, () async {
        final fileSource = await TestUtil.createFileWithHistory(proceedSeconds);
        final fileSource2 = await TestUtil.saveAndRead(fileSource);

        fileSource.body.rootGroup.entries.values
            .toList()[0]
            .setString(KdbxKeyCommon.USER_NAME, PlainValue('test4local'));
        await TestUtil.saveAndRead(fileSource);
        proceedSeconds(10);
        fileSource2.body.rootGroup.entries.values
            .toList()[0]
            .setString(KdbxKeyCommon.USER_NAME, PlainValue('test4remote'));
        await TestUtil.saveAndRead(fileSource2);

        proceedSeconds(10);

        fileSource.body.rootGroup.entries.values
            .toList()[0]
            .setString(KdbxKeyCommon.USER_NAME, PlainValue('test5local'));
        final fileLocal = await TestUtil.saveAndRead(fileSource);
        proceedSeconds(10);
        fileSource2.body.rootGroup.entries.values
            .toList()[0]
            .setString(KdbxKeyCommon.USER_NAME, PlainValue('test5remote'));
        final fileRemote = await TestUtil.saveAndRead(fileSource2);

        final merge = fileLocal.merge(fileRemote);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(2));
        expect(
            fileLocal.body.rootGroup.entries.values
                .toList()[0]
                .history
                .map((e) => e.getString(KdbxKeyCommon.USER_NAME)!.getText())
                .toList(),
            [
              'test1',
              'test2',
              'test3',
              'test4local',
              'test4remote',
              'test5local',
            ]);
        expect(
            fileLocal.body.rootGroup.entries.values
                .toList()[0]
                .getString(KdbxKeyCommon.USER_NAME)!
                .getText(),
            'test5remote');
      }),
    );
  });

  group('Credential merges', () {
    test(
      'Overwrites older credentials',
      () async => await withClock(fakeClock, () async {
        final file1 = await TestUtil.createSimpleFile(proceedSeconds);

        final fileMod = await TestUtil.saveAndRead(file1);
        fileMod.changePassword('newPass');

        final file2 = await TestUtil.saveAndRead(fileMod);
        final initialSalt2 = KdfField.salt.read(file2.header.readKdfParameters);
        expect(file1.credentials.getHash(),
            Credentials(ProtectedValue('asdf')).getHash());
        final merge = file1.merge(file2);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(4));
        expect(file1.credentials.getHash(),
            Credentials(ProtectedValue('newPass')).getHash());
        expect(file1.body.meta.masterKeyChanged.get(),
            DateTime.fromMillisecondsSinceEpoch(10000, isUtc: true));
        expect(
            initialSalt2, KdfField.salt.read(file1.header.readKdfParameters));
        expect(
            initialSalt2, KdfField.salt.read(file2.header.readKdfParameters));
      }),
    );
    test(
      'Retains newer credentials',
      () async => await withClock(fakeClock, () async {
        final file1 = await TestUtil.createSimpleFile(proceedSeconds);
        final initialSalt1 = KdfField.salt.read(file1.header.readKdfParameters);

        final fileMod = await TestUtil.saveAndRead(file1);
        fileMod.changePassword('newPass');

        final file2 = await TestUtil.saveAndRead(fileMod);
        final initialSalt2 = KdfField.salt.read(file2.header.readKdfParameters);
        final merge = file2.merge(file1);
        final set = Set<KdbxUuid>.from(merge.merged.keys);
        expect(set, hasLength(4));
        expect(file1.credentials.getHash(),
            Credentials(ProtectedValue('asdf')).getHash());
        expect(file1.body.meta.masterKeyChanged.get(),
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
        expect(file2.credentials.getHash(),
            Credentials(ProtectedValue('newPass')).getHash());
        expect(file2.body.meta.masterKeyChanged.get(),
            DateTime.fromMillisecondsSinceEpoch(10000, isUtc: true));
        expect(
            initialSalt1, KdfField.salt.read(file1.header.readKdfParameters));
        expect(
            initialSalt2, KdfField.salt.read(file2.header.readKdfParameters));
      }),
    );
  });

  group('Binary merges', () {
    test(
      'when entry with a binary is added remotely, merge results in local file with that binary included in the header',
      () async => await withClock(fakeClock, () async {
        final fileLocal = await TestUtil.createRealFile(proceedSeconds);
        final fileMod = await TestUtil.saveAndRead(fileLocal);
        final entry = KdbxEntry.create(fileMod, fileMod.body.rootGroup);
        fileMod.body.rootGroup.addEntry(entry);
        entry.createBinary(
            isProtected: false,
            name: 'testBin1',
            bytes: Uint8List.fromList([1, 2, 3]));
        final fileRemote = await TestUtil.saveAndRead(fileMod);
        expect(fileLocal.ctx.binariesIterable.length, 0);
        fileLocal.merge(fileRemote);
        expect(fileLocal.ctx.binariesIterable.length, 1);
        expect(fileLocal.body.rootGroup.entries.length, 2);
        expect(fileLocal.ctx.binariesIterable.first.value,
            Uint8List.fromList([1, 2, 3]));
        expectBinary(fileLocal.body.rootGroup.entries.values.toList()[1],
            'testBin1', hasLength(3));
      }),
    );

    test(
      'when binary is added to entry remotely, merge results in local file with that binary included in the header',
      () async => await withClock(fakeClock, () async {
        final fileLocal = await TestUtil.createRealFile(proceedSeconds);

        final fileMod = await TestUtil.saveAndRead(fileLocal);
        final entry = fileMod.body.rootGroup.entries.first;
        entry.createBinary(
            isProtected: false,
            name: 'testBin1',
            bytes: Uint8List.fromList([1, 2, 3]));
        final fileRemote = await TestUtil.saveAndRead(fileMod);
        expect(fileLocal.ctx.binariesIterable.length, 0);
        fileLocal.merge(fileRemote);
        expect(fileLocal.ctx.binariesIterable.length, 1);
        expect(fileLocal.body.rootGroup.entries.length, 1);

        expect(fileLocal.ctx.binariesIterable.first.value,
            Uint8List.fromList([1, 2, 3]));
        expectBinary(
            fileLocal.body.rootGroup.entries.first, 'testBin1', hasLength(3));
      }),
    );

    test(
      'when entry with a binary is permanently deleted remotely, merge results in local file with that binary removed from the header',
      () async => await withClock(fakeClock, () async {
        final fileLocal =
            await TestUtil.readKdbxFile('test/keepass2kdbx4binaries.kdbx');
        final binaryThatShouldRemain = fileLocal.ctx.binariesIterable.last;

        final fileMod =
            await TestUtil.readKdbxFile('test/keepass2kdbx4binaries.kdbx');
        final entry = fileMod.body.rootGroup.entries.first;
        fileMod.deleteEntry(entry, true);
        final fileRemote = await TestUtil.saveAndRead(fileMod);
        expect(fileLocal.ctx.binariesIterable.length, 2);
        fileLocal.merge(fileRemote);
        expect(fileLocal.ctx.binariesIterable.length, 1);
        expect(fileLocal.body.rootGroup.entries.length, 1);
        expect(fileLocal.ctx.binariesIterable.first.value,
            binaryThatShouldRemain.value);
      }),
    );

    test(
      'when entry A with a binary is in the recycle bin locally and remotely and entry B with a binary is permanently deleted remotely, merge results in local file with just entry B\'s binary removed from the header',
      () async => await withClock(fakeClock, () async {
        final fileBase =
            await TestUtil.readKdbxFile('test/keepass2kdbx4binaries.kdbx');
        final entryToRecycle = fileBase.body.rootGroup.entries.first;
        fileBase.deleteEntry(entryToRecycle, false);
        final fileLocal = await TestUtil.saveAndRead(fileBase);
        final fileMod = await TestUtil.saveAndRead(fileBase);
        final binaryThatShouldRemain = fileLocal.ctx.binariesIterable.first;
        final entryToDelete = fileMod.body.rootGroup.entries.first;
        fileMod.deleteEntry(entryToDelete, true);

        // saving implicitly cleans out the old binary
        final fileRemote = await TestUtil.saveAndRead(fileMod);
        expect(fileLocal.ctx.binariesIterable.length, 2);
        fileLocal.merge(fileRemote);
        expect(fileLocal.ctx.binariesIterable.length, 1);
        expect(fileLocal.body.rootGroup.entries.length, 0);
        expect(fileLocal.ctx.binariesIterable.first.value,
            binaryThatShouldRemain.value);
      }),
    );
  });

  // group('Kdbx4.1 merges', () {
  //   Future<KdbxFile> TestUtil.createRealFile(proceedSeconds) async {
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
  //       final file = await TestUtil.createRealFile(proceedSeconds);

  //       final fileMod = await TestUtil.saveAndRead(file);
  //     });
  //   });
  // });
}
