// ignore_for_file: invalid_use_of_protected_member

@Tags(['kdbx4'])

import 'dart:io';

import 'package:clock/clock.dart';
import 'package:kdbx/kdbx.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';
import 'package:test/test.dart';

import 'internal/test_utils.dart';

final _logger = Logger('kdbx4_customdata_test');

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

  group('CustomData', () {
    test('CustomData works on entries and groups', () async {
      final credentials = Credentials(ProtectedValue.fromString('asdf'));
      final kdbx = kdbxFormat.create(
        credentials,
        'Test Keystore',
        header: KdbxHeader.createV4(),
      );
      final rootGroup = kdbx.body.rootGroup;
      final e1 = TestUtil.createEntry(kdbx, rootGroup, 'user1', 'LoremIpsum');
      expect(e1.customData.entries.length, 0);
      expect(rootGroup.customData.entries.length, 0);
      e1.customData['tcd1'] = 'tv1';
      rootGroup.customData['tcd2'] = 'tv2';

      final saved = await kdbx.save();

      final loadedKdbx = await kdbxFormat.read(
          saved, Credentials(ProtectedValue.fromString('asdf')));

      _logger.fine('Successfully loaded kdbx $loadedKdbx');
      final entry1 = loadedKdbx.body.rootGroup.entries.first;
      expect(entry1.customData['tcd1'], 'tv1');
      expect(rootGroup.customData['tcd2'], 'tv2');
    });
  });
}
