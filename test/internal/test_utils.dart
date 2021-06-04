//typedef HashStuff = Pointer<Utf8> Function(Pointer<Utf8> str);
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:argon2_ffi_base/argon2_ffi_base.dart';
import 'package:kdbx/kdbx.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';

final _logger = Logger('test_utils');

class TestUtil {
  static final keyTitle = KdbxKey('Title');

  static void setupLogging() =>
      PrintAppender.setupLogging(stderrLevel: Level.WARNING);

  static KdbxFormat kdbxFormat() {
    Argon2.resolveLibraryForceDynamic = true;
    return KdbxFormat(Argon2FfiFlutter(resolveLibrary: (path) {
      final cwd = Directory('.').absolute.uri;
      final p = cwd.resolve(path);
      final filePath = p.toFilePath();
      _logger.fine('Resolving $path to: $filePath (${Platform.script})');
      return filePath;
    }));
  }

  static Future<KdbxFile> readKdbxFile(
    String filePath, {
    String password = 'asdf',
  }) async {
    final kdbxFormat = TestUtil.kdbxFormat();
    final data = await File(filePath).readAsBytes();
    final file = await kdbxFormat.read(
        data, Credentials(ProtectedValue.fromString(password)));
    return file;
  }

  static Future<KdbxFile> readKdbxFileBytes(Uint8List data,
      {String password = 'asdf', Credentials? credentials}) async {
    final kdbxFormat = TestUtil.kdbxFormat();
    final file = await kdbxFormat.read(
        data, credentials ?? Credentials(ProtectedValue.fromString(password)));
    return file;
  }

  static Future<KdbxFile> saveAndRead(KdbxFile file) async {
    return await readKdbxFileBytes(await file.save(),
        credentials: Credentials.fromHash(file.credentials.getHash()));
  }

  static Future<void> saveTestOutput(String name, KdbxFile file) async {
    final bytes = await file.save();
    final outFile = File('test_output_$name.kdbx');
    await outFile.writeAsBytes(bytes);
    _logger.info('Written to $outFile');
  }

  static KdbxFile createEmptyFile() {
    return createEmptyFileWithCredentials(
        Credentials.composite(ProtectedValue.fromString('asdf'), null));
  }

  static KdbxFile createEmptyFileWithCredentials(Credentials credentials) {
    return kdbxFormat().create(credentials, 'example');
  }

  static Future<KdbxFile> createFileWithHistory(Function proceedSeconds) async {
    final file = TestUtil.createEmptyFile();
    final entry = _createEntry(file, file.body.rootGroup, 'test1', 'test1');
    await TestUtil.saveAndRead(file);
    proceedSeconds(1);
    entry.setString(KdbxKeyCommon.USER_NAME, PlainValue('test2'));
    await TestUtil.saveAndRead(file);
    proceedSeconds(1);
    entry.setString(KdbxKeyCommon.USER_NAME, PlainValue('test3'));
    proceedSeconds(10);
    return await TestUtil.saveAndRead(file);
  }

  static Future<KdbxFile> createSimpleFile(Function proceedSeconds) async {
    final file = TestUtil.createEmptyFile();
    _createEntry(file, file.body.rootGroup, 'test1', 'test1');
    final subGroup =
        file.createGroup(parent: file.body.rootGroup, name: 'Sub Group');
    _createEntry(file, subGroup, 'test2', 'test2');
    proceedSeconds(10);
    return await TestUtil.saveAndRead(file);
  }

  static Future<KdbxFile> createSimpleFileWithCredentials(
      Function proceedSeconds, Credentials credentials) async {
    final file = TestUtil.createEmptyFileWithCredentials(credentials);
    _createEntry(file, file.body.rootGroup, 'test1', 'test1');
    final subGroup =
        file.createGroup(parent: file.body.rootGroup, name: 'Sub Group');
    _createEntry(file, subGroup, 'test2', 'test2');
    proceedSeconds(10);
    return await TestUtil.saveAndRead(file);
  }

  static Future<KdbxFile> createRealFile(Function proceedSeconds) async {
    final file = TestUtil.createEmptyFile();
    _createEntry(file, file.body.rootGroup, 'test1', 'test1');
    final subGroup =
        file.createGroup(parent: file.body.rootGroup, name: 'Sub Group');
    _createEntry(file, subGroup, 'test2', 'test2');
    file.createGroup(parent: file.body.rootGroup, name: 'Sub Group 2');
    proceedSeconds(10);
    return await TestUtil.saveAndRead(file);
  }

  static Future<KdbxFile> createGroupMergeFile(Function proceedSeconds) async {
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

  static KdbxEntry _createEntry(
      KdbxFile file, KdbxGroup group, String username, String password) {
    final entry = KdbxEntry.create(file, group);
    group.addEntry(entry);
    entry.setString(KdbxKeyCommon.USER_NAME, PlainValue(username));
    entry.setString(
        KdbxKeyCommon.PASSWORD, ProtectedValue.fromString(password));
    return entry;
  }
}

extension UnmodifiableMapViewKdbxObject<K extends String, V extends KdbxObject>
    on UnmodifiableMapView<K, V> {
  V get first {
    return values.first;
  }

  V get last {
    return values.last;
  }

  V firstWhere(bool Function(V) test, {V Function()? orElse}) =>
      values.firstWhere(test, orElse: orElse);
}
