import 'dart:async';
//import 'dart:html';

import 'package:clock/clock.dart';
import 'package:kdbx/kdbx.dart';
import 'package:quiver/core.dart';
import 'package:test/test.dart';

import 'internal/test_utils.dart';

class StreamExpect<T> {
  StreamExpect(this.stream) {
    stream.listen((event) {
      if (_expectNext == null) {
        fail('Got event, but none was expected. $event');
      }
      expect(event, _expectNext!.orNull);
      _expectNext = null;
    }, onDone: () {
      expect(_expectNext, isNull);
      isDone = true;
    }, onError: (dynamic error) {
      expect(_expectNext, isNull);
      this.error = error;
    });
  }

  Future<RET> expectNext<RET>(T value, FutureOr<RET> Function() cb) async {
    if (_expectNext != null) {
      fail('The last event was never received. last: $_expectNext');
    }
    _expectNext = Optional.fromNullable(value);
    try {
      return await cb();
    } finally {
      await pumpEventQueue();
    }
  }

  void expectFinished() {
    expect(isDone, true);
  }

  final Stream<T> stream;
  bool isDone = false;
  dynamic error;
  Optional<T>? _expectNext;
}

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
  group('test history for values', () {
    test('check history creation', () async {
      final file = await TestUtil.readKdbxFile('test/keepass2test.kdbx');
      const valueOrig = 'Sample Entry';
      const value1 = 'new';
      const value2 = 'new2';
      final dirtyExpect = StreamExpect(file.dirtyObjectsChanged);
      {
        final first = file.body.rootGroup.entries.first;
        expect(file.header.version.major, 3);
        expect(first.getString(TestUtil.keyTitle)!.getText(), valueOrig);
        await dirtyExpect.expectNext({first}, () async {
          first.setString(TestUtil.keyTitle, PlainValue(value1));
        });
      }
      expect(file.dirtyObjects, hasLength(1));
      final f2 = await dirtyExpect
          .expectNext({}, () async => TestUtil.saveAndRead(file));
      expect(file.dirtyObjects, isEmpty);
      {
        final first = f2.body.rootGroup.entries.first;
        expect(first.getString(TestUtil.keyTitle)!.getText(), value1);
        expect(first.history.last.getString(TestUtil.keyTitle)!.getText(),
            valueOrig);
        await dirtyExpect.expectNext({}, () async => file.save());
      }

      // edit the original file again, and there should be a second history
      {
        final first = file.body.rootGroup.entries.first;
        await dirtyExpect.expectNext({first},
            () async => first.setString(TestUtil.keyTitle, PlainValue(value2)));
      }
      final f3 = await dirtyExpect
          .expectNext({}, () async => TestUtil.saveAndRead(file));
      expect(file.dirtyObjects, isEmpty);
      {
        final first = f3.body.rootGroup.entries.first;
        expect(first.getString(TestUtil.keyTitle)!.getText(), value2);
        expect(first.history, hasLength(2));
        expect(
            first.history.last.getString(TestUtil.keyTitle)!.getText(), value1);
        expect(first.history.first.getString(TestUtil.keyTitle)!.getText(),
            valueOrig);
        await dirtyExpect.expectNext({}, () async => file.save());
      }
      file.dispose();
      await pumpEventQueue();
      dirtyExpect.expectFinished();
    });

    test(
      'reverts 1st history item',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createFileWithHistory(proceedSeconds);
        proceedSeconds(10);
        final expectedFinalModifiedDate = now.toUtc();
        final entry = file.body.rootGroup.entries.values.toList()[0];
        entry.revertToHistoryEntry(entry.history.length - 1);
        final history = entry.history;
        proceedSeconds(10);
        expect(history.length, 3);
        final history_1 = history.last;
        final history_2 = history[history.length - 2];
        final history_3 = history[history.length - 3];
        expect(
            history_1.getString(KdbxKeyCommon.USER_NAME)!.getText(), 'test3');
        expect(
            history_2.getString(KdbxKeyCommon.USER_NAME)!.getText(), 'test2');
        expect(
            history_3.getString(KdbxKeyCommon.USER_NAME)!.getText(), 'test1');
        expect(entry.getString(KdbxKeyCommon.USER_NAME)!.getText(), 'test2');
        expect(entry.times.lastModificationTime.get()!.toUtc(),
            expectedFinalModifiedDate);
        expect(entry.times.creationTime.get()!.toUtc(),
            DateTime.fromMillisecondsSinceEpoch(0).toUtc());
        expect(history_1.times.lastModificationTime.get()!.toUtc(),
            isNot(expectedFinalModifiedDate));
      }),
    );

    test(
      'reverts 2nd history item',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createFileWithHistory(proceedSeconds);
        proceedSeconds(10);
        final expectedFinalModifiedDate = now.toUtc();
        final entry = file.body.rootGroup.entries.values.toList()[0];
        entry.revertToHistoryEntry(entry.history.length - 2);
        final history = entry.history;
        proceedSeconds(10);
        expect(history.length, 3);
        final history_1 = history.last;
        final history_2 = history[history.length - 2];
        final history_3 = history[history.length - 3];
        expect(
            history_1.getString(KdbxKeyCommon.USER_NAME)!.getText(), 'test3');
        expect(
            history_2.getString(KdbxKeyCommon.USER_NAME)!.getText(), 'test2');
        expect(
            history_3.getString(KdbxKeyCommon.USER_NAME)!.getText(), 'test1');
        expect(entry.getString(KdbxKeyCommon.USER_NAME)!.getText(), 'test1');
        expect(entry.times.lastModificationTime.get()!.toUtc(),
            expectedFinalModifiedDate);
        expect(entry.times.creationTime.get()!.toUtc(),
            DateTime.fromMillisecondsSinceEpoch(0).toUtc());
        expect(history_1.times.lastModificationTime.get()!.toUtc(),
            isNot(expectedFinalModifiedDate));
      }),
    );
    test(
      'revert then edit does not duplicate current state',
      () async => await withClock(fakeClock, () async {
        final file = await TestUtil.createFileWithHistory(proceedSeconds);
        proceedSeconds(10);
        final expectedFinalModifiedDate = now.toUtc();
        final entry = file.body.rootGroup.entries.values.toList()[0];
        entry.revertToHistoryEntry(entry.history.length - 1);
        entry.setString(KdbxKeyCommon.USER_NAME, PlainValue('test4'));
        final history = entry.history;
        proceedSeconds(10);
        expect(history.length, 3);
        final history_1 = history.last;
        final history_2 = history[history.length - 2];
        expect(
            history_1.getString(KdbxKeyCommon.USER_NAME)!.getText(), 'test3');
        expect(
            history_2.getString(KdbxKeyCommon.USER_NAME)!.getText(), 'test2');
        expect(entry.getString(KdbxKeyCommon.USER_NAME)!.getText(), 'test4');
        expect(entry.times.lastModificationTime.get()!.toUtc(),
            expectedFinalModifiedDate);
        expect(entry.times.creationTime.get()!.toUtc(),
            DateTime.fromMillisecondsSinceEpoch(0).toUtc());
        expect(history_1.times.lastModificationTime.get()!.toUtc(),
            isNot(expectedFinalModifiedDate));
      }),
    );
    test(
      'reverts custom json field from history item',
      () async => await withClock(fakeClock, () async {
        final file =
            await TestUtil.createFileWithJsonFieldHistory(proceedSeconds);
        proceedSeconds(10);
        final entry = file.body.rootGroup.entries.values.toList()[0];
        expect(entry.browserSettings.fields?.length ?? 0, 0);
        entry.revertToHistoryEntry(entry.history.length - 1);
        final history = entry.history;
        proceedSeconds(10);
        expect(history.length, 2);
        final history_1 = history.last;
        final history_2 = history[history.length - 2];
        expect(
            history_1.getString(KdbxKeyCommon.USER_NAME)!.getText(), 'test2');
        expect(
            history_2.getString(KdbxKeyCommon.USER_NAME)!.getText(), 'test1');
        expect(entry.getString(KdbxKeyCommon.USER_NAME)!.getText(), 'test1');
        expect(entry.browserSettings.fields?.length ?? 0, 1);
      }),
    );
  }, tags: ['kdbx3']);
}
