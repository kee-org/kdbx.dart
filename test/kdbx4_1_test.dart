@Tags(['kdbx4_1'])

import 'dart:io';

import 'package:clock/clock.dart';
import 'package:kdbx/kdbx.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';
import 'package:test/test.dart';

import 'internal/test_utils.dart';

final _logger = Logger('kdbx4_1_test');

// ignore_for_file: non_constant_identifier_names

void main() {
  Logger.root.level = Level.ALL;
  PrintAppender().attachToLogger(Logger.root);
  final kdbxFormat = TestUtil.kdbxFormat();
  if (!kdbxFormat.argon2.isFfi) {
    throw StateError('Expected ffi!');
  }
  var now = DateTime.fromMillisecondsSinceEpoch(0);

  final fakeClock = Clock(() => now);
  void proceedSeconds(int seconds) {
    now = now.add(Duration(seconds: seconds));
  }

  setUp(() {
    now = DateTime.fromMillisecondsSinceEpoch(0);
  });

  group('11111111111111', () {
    //   test('TODO', () async {
    //     final file = await TestUtil.readKdbxFile('test/kdbx4.kdbx');
    //     //final file = await TestUtil.readKdbxFile('test/kdbx4_1.kdbx');
    //     final firstEntry = file.body.rootGroup.entries.first;
    //     final d = DateTime.utc(2020, 4, 5, 10, 0);
    //     firstEntry.times.lastModificationTime.set(d);
    //     final saved = await file.save();
    //     {
    //       final file2 = await TestUtil.readKdbxFileBytes(saved);
    //       final firstEntry = file2.body.rootGroup.entries.first;
    //       expect(firstEntry.times.lastModificationTime.get(), d);
    //     }
    //   });

    // Probably should do similar to make v3 more robust too but we don't use that and there's no risk of regression so not now.
    test('New features fail on v4.0', () async {
      final credentials = Credentials(ProtectedValue.fromString('asdf'));
      final kdbx = kdbxFormat.create(
        credentials,
        'Test Keystore',
        header: KdbxHeader.createV4(),
      );
      final rootGroup = kdbx.body.rootGroup;
      final e1 = TestUtil.createEntry(kdbx, rootGroup, 'user1', 'LoremIpsum');
      final e2 =
          TestUtil.createEntry(kdbx, rootGroup, 'user2', 'Second Password');
      rootGroup.tags.set(['t1', 't2']);
      e1.qualityCheck.set(true);
      e2.qualityCheck.set(false);
      final saved = await kdbx.save();

      final loadedKdbx = await kdbxFormat.read(
          saved, Credentials(ProtectedValue.fromString('asdf')));
      //final file2 = await TestUtil.readKdbxFileBytes(saved);

      _logger.fine('Successfully loaded kdbx $loadedKdbx');
      final entry1 = loadedKdbx.body.rootGroup.entries.first;
      final entry2 = loadedKdbx.body.rootGroup.entries.last;
      expect(entry1.qualityCheck.get(), null);
      expect(entry2.qualityCheck.get(), null);
      expect(loadedKdbx.body.rootGroup.tags.get(), null);
    });

    test('Tags work on entries and groups', () async {
      final credentials = Credentials(ProtectedValue.fromString('asdf'));
      final kdbx = kdbxFormat.create(
        credentials,
        'Test Keystore',
        header: KdbxHeader.createV4_1(),
      );
      final rootGroup = kdbx.body.rootGroup;
      final e = TestUtil.createEntry(kdbx, rootGroup, 'user1', 'LoremIpsum');
      TestUtil.createEntry(kdbx, rootGroup, 'user2', 'Second Password');
      rootGroup.tags.set(['t1', 't2']);
      e.tags.set(['t3', 't4']);
      final saved = await kdbx.save();

      final loadedKdbx = await kdbxFormat.read(
          saved, Credentials(ProtectedValue.fromString('asdf')));
      //final file2 = await TestUtil.readKdbxFileBytes(saved);

      _logger.fine('Successfully loaded kdbx $loadedKdbx');
      final firstEntry = loadedKdbx.body.rootGroup.entries.first;
      expect(loadedKdbx.body.rootGroup.tags.get(), ['t1', 't2']);
      expect(firstEntry.tags.get(), ['t3', 't4']);
    });

    test('Entry password quality estimation', () async {
      final credentials = Credentials(ProtectedValue.fromString('asdf'));
      final kdbx = kdbxFormat.create(
        credentials,
        'Test Keystore',
        header: KdbxHeader.createV4_1(),
      );
      final rootGroup = kdbx.body.rootGroup;
      final e1 = TestUtil.createEntry(kdbx, rootGroup, 'user1', 'LoremIpsum');
      final e2 =
          TestUtil.createEntry(kdbx, rootGroup, 'user2', 'Second Password');
      expect(e1.qualityCheck.get(), null);
      e1.qualityCheck.set(true);
      e2.qualityCheck.set(false);
      final saved = await kdbx.save();

      final loadedKdbx = await kdbxFormat.read(
          saved, Credentials(ProtectedValue.fromString('asdf')));

      _logger.fine('Successfully loaded kdbx $loadedKdbx');
      final entry1 = loadedKdbx.body.rootGroup.entries.first;
      final entry2 = loadedKdbx.body.rootGroup.entries.last;
      expect(entry1.qualityCheck.get(), true);
      expect(entry2.qualityCheck.get(), false);
    });
  });
}
