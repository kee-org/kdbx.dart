@Tags(['kdbx4'])

import 'package:clock/clock.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:kdbx/kdbx.dart';

import 'internal/test_utils.dart';

final _logger = Logger('deleted_objects_test');

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

  _logger.finest('Running deleted objects tests.');
  group('read tombstones', () {
    test('load/save keeps deleted objects.', () async {
      final orig =
          await TestUtil.readKdbxFile('test/test_files/tombstonetest.kdbx');
      expect(orig.body.deletedObjects, hasLength(1));
      final dt = orig.body.deletedObjects.first.deletionTime.get()!;
      expect([dt.year, dt.month, dt.day], [2020, 8, 30]);
      final reload = await TestUtil.saveAndRead(orig);
      expect(reload.body.deletedObjects, hasLength(1));
    });
  });

  group('deleting objects', () {
    test(
      'Delete entry creates a deletedObject',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createSimpleFile(proceedSeconds);
        final removedUuid = file.body.rootGroup.entries.first.uuid.uuid;

        expect(file.recycleBin, isNull);
        expect(file.body.deletedObjects, hasLength(0));

        file.deleteEntry(file.body.rootGroup.entries.first, true);
        final wasRemoved =
            !file.body.rootGroup.getAllEntries().keys.contains(removedUuid);
        expect(wasRemoved, true);
        expect(file.recycleBin, isNull);
        expect(file.body.deletedObjects, hasLength(1));
        expect(
            file.body.deletedObjects
                .any((deletedObj) => deletedObj.uuid.uuid == removedUuid),
            true);
      }),
    );
    test(
      'Delete group creates a deletedObject',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createRealFile(proceedSeconds);
        final removedUuid =
            file.body.rootGroup.groups.values.toList()[1].uuid.uuid;

        expect(file.recycleBin, isNull);
        expect(file.body.deletedObjects, hasLength(0));

        file.deleteGroup(file.body.rootGroup.groups.values.toList()[1], true);
        final wasRemoved =
            !file.body.rootGroup.getAllGroups().keys.contains(removedUuid);
        expect(wasRemoved, true);
        expect(file.recycleBin, isNull);
        expect(file.body.deletedObjects, hasLength(1));
        expect(
            file.body.deletedObjects
                .any((deletedObj) => deletedObj.uuid.uuid == removedUuid),
            true);
      }),
    );
    test(
      'Deleting group recursively creates required deletedObjects',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createReursiveGroupFile(proceedSeconds);
        final startGroup = file.body.rootGroup.groups.first;
        final removedUuids = [
          startGroup.uuid.uuid,
          startGroup.entries.first.uuid.uuid,
          startGroup.groups.first.uuid.uuid,
          startGroup.groups.first.entries.first.uuid.uuid,
        ];

        expect(file.recycleBin, isNull);
        expect(file.body.deletedObjects, hasLength(0));

        file.deleteGroup(startGroup, true);

        final remainingKeys = file.body.rootGroup.getAllGroups().keys;
        expect(remainingKeys, isNot(contains(removedUuids[0])));
        expect(remainingKeys, isNot(contains(removedUuids[1])));
        expect(remainingKeys, isNot(contains(removedUuids[2])));
        expect(remainingKeys, isNot(contains(removedUuids[3])));
        expect(file.recycleBin, isNull);
        expect(file.body.deletedObjects, hasLength(4));
        final deletedObjects = file.body.deletedObjects.map((d) => d.uuid.uuid);
        expect(deletedObjects, contains(removedUuids[0]));
        expect(deletedObjects, contains(removedUuids[1]));
        expect(deletedObjects, contains(removedUuids[2]));
        expect(deletedObjects, contains(removedUuids[3]));
      }),
    );
  });
}
