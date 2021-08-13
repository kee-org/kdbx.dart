import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:kdbx/src/crypto/protected_value.dart';
import 'package:kdbx/src/kdbx_consts.dart';
import 'package:kdbx/src/kdbx_dao.dart';
import 'package:kdbx/src/kdbx_exceptions.dart';
import 'package:kdbx/src/kdbx_format.dart';
import 'package:kdbx/src/kdbx_group.dart';
import 'package:kdbx/src/kdbx_header.dart';
import 'package:kdbx/src/kdbx_object.dart';
import 'package:logging/logging.dart';
import 'package:quiver/check.dart';
import 'package:synchronized/synchronized.dart';
import 'package:xml/xml.dart' as xml;

final _logger = Logger('kdbx_file');

class KdbxFile {
  KdbxFile(
      this.ctx, this.kdbxFormat, this._credentials, this.header, this.body) {
    for (final obj in _allObjects) {
      obj.file = this;
    }
  }

  static final protectedValues = Expando<ProtectedValue>();

  static ProtectedValue? protectedValueForNode(xml.XmlElement node) {
    return protectedValues[node];
  }

  static void setProtectedValueForNode(
      xml.XmlElement node, ProtectedValue value) {
    protectedValues[node] = value;
  }

  final KdbxFormat kdbxFormat;
  final KdbxReadWriteContext ctx;
  Credentials _credentials;
  Credentials get credentials => _credentials;
  final KdbxHeader header;
  final KdbxBody body;
  final Set<KdbxObject> dirtyObjects = {};
  bool get isDirty => dirtyObjects.isNotEmpty;
  final StreamController<Set<KdbxObject>> _dirtyObjectsChanged =
      StreamController<Set<KdbxObject>>.broadcast();

  /// lock used by [KdbxFormat] to synchronize saves,
  /// because save actions are not thread save.
  /// see [KdbxFileInternal.saveLock].
  final Lock _saveLock = Lock();

  Stream<Set<KdbxObject>> get dirtyObjectsChanged =>
      _dirtyObjectsChanged.stream;

  Future<Uint8List> save() async {
    return kdbxFormat.save(this);
  }

  /// Marks all dirty objects as clean. Called by [KdbxFormat.save].
  void onSaved() {
    dirtyObjects.clear();
    _dirtyObjectsChanged.add(const {});
  }

  Iterable<KdbxObject> get _allObjects => body.rootGroup
      .getAllGroups()
      .values
      .cast<KdbxObject>()
      .followedBy(body.rootGroup.getAllEntries().values);

  void dirtyObject(KdbxObject kdbxObject) {
    dirtyObjects.add(kdbxObject);
    _dirtyObjectsChanged.add(UnmodifiableSetView(Set.of(dirtyObjects)));
  }

  void changePassword(String password) {
    _credentials = Credentials(ProtectedValue(password));
    body.meta.masterKeyChanged.setToNow();
  }

  void overwriteCredentials(Credentials credentials, DateTime timestamp) {
    _credentials = credentials;
    body.meta.masterKeyChanged.set(timestamp);

    // We don't change masterKeyChanged because this is only used when either:
    // 1. we are uploading after a merge from a more recent remote file, which will have a newer datestamp anyway
    // 2. we are upoloading when no more recent version exists...
  }

  void changeCredentials(Credentials credentials) {
    _credentials = credentials;
    body.meta.masterKeyChanged.setToNow();
  }

  void dispose() {
    _dirtyObjectsChanged.close();
  }

  List<String>? _tags;

  List<String> get tags {
    _tags ??= body.rootGroup
        .getAllEntries()
        .values
        .map((e) => e.tags.get() ?? [])
        .flatten()
        .toSet()
        .toList();
    return _tags!;
  }

  void clearTagsCache() {
    _tags = null;
  }

  CachedValue<KdbxGroup>? _recycleBin;

  /// Returns the recycle bin, if it exists, null otherwise.
  KdbxGroup? get recycleBin => (_recycleBin ??= _findRecycleBin()).value;

  CachedValue<KdbxGroup> _findRecycleBin() {
    final uuid = body.meta.recycleBinUUID.get();
    if (uuid?.isNil != false) {
      return CachedValue.withNull();
    }
    try {
      return CachedValue.withValue(findGroupByUuid(uuid!));
    } catch (e, stackTrace) {
      _logger.warning(() {
        final groupDebug = body.rootGroup
            .getAllGroups()
            .values
            .map((g) => '${g.uuid}: ${g.name}')
            .join('\n');
        return 'All Groups: $groupDebug';
      });
      _logger.severe('Inconsistency error, uuid $uuid not found in groups.', e,
          stackTrace);
      return CachedValue.withNull();
    }
  }

  KdbxGroup _createRecycleBin() {
    body.meta.recycleBinEnabled.set(true);
    final group = createGroup(parent: body.rootGroup, name: 'Trash');
    group.icon.set(KdbxIcon.TrashBin);
    group.enableAutoType.set(false);
    group.enableSearching.set(false);
    body.meta.recycleBinUUID.set(group.uuid);
    _recycleBin = CachedValue.withValue(group);
    return group;
  }

  KdbxGroup getRecycleBinOrCreate() {
    return recycleBin ?? _createRecycleBin();
  }

  /// Upgrade v3 file to v4.
  void upgrade(int majorVersion) {
    checkArgument(majorVersion == 4, message: 'Must be majorVersion 4');
    body.meta.settingsChanged.setToNow();
    body.meta.headerHash.remove();
    header.upgrade(majorVersion);
  }

  /// Merges the given file into this file.
  /// Both files must have the same origin (ie. same root group UUID).
  MergeContext merge(KdbxFile other) {
    if (other.body.rootGroup.uuid != body.rootGroup.uuid) {
      throw KdbxUnsupportedException(
          'Root groups of source and dest file do not match.');
    }

    if (other.body.meta.masterKeyChanged.isAfter(body.meta.masterKeyChanged)) {
      _credentials = other.credentials;
      _logger.finest('Changing MasterKey.');
    }
    return body.merge(other.body);
  }
}

extension KdbxInternal on KdbxFile {
  Lock get saveLock => _saveLock;
}

class CachedValue<T> {
  CachedValue.withNull() : value = null;
  CachedValue.withValue(this.value) : assert(value != null);

  final T? value;
}
