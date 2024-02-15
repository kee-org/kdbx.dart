import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:kdbx/kdbx.dart';
import 'package:kdbx/src/kdbx_format.dart';
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
    changeCredentials(Credentials(ProtectedValue(password)));
  }

  void changeCredentials(Credentials credentials) {
    _credentials = credentials;
    body.meta.masterKeyChanged.setToNow();
    header.regenerateArgon2Salt();
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
        .expand((element) => element)
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

  /// Upgrade v3 file to v4.x
  void upgrade(int majorVersion, int minorVersion) {
    checkArgument(majorVersion == 4, message: 'Must be majorVersion 4');
    body.meta.headerHash.remove();
    header.version.major == 4
        ? header.upgradeMinor(majorVersion, minorVersion)
        : header.upgrade(majorVersion, minorVersion);

    upgradeDateTimeFormatV4();

    body.meta.settingsChanged.setToNow();
  }

  void upgradeDateTimeFormatV4() {
    body.meta.databaseNameChanged.upgrade();
    body.meta.databaseDescriptionChanged.upgrade();
    body.meta.defaultUserNameChanged.upgrade();
    body.meta.masterKeyChanged.upgrade();
    body.meta.recycleBinChanged.upgrade();
    body.meta.entryTemplatesGroupChanged.upgrade();
    body.meta.settingsChanged.upgrade();
    body.rootGroup.getAllGroups().values.forEach(upgradeAllObjectTimesV4);
    body.rootGroup.getAllEntries().values.forEach(upgradeAllObjectTimesV4);
  }

  void upgradeAllObjectTimesV4(KdbxObject obj) {
    obj.times.creationTime.upgrade();
    obj.times.lastModificationTime.upgrade();
    obj.times.lastAccessTime.upgrade();
    obj.times.expiryTime.upgrade();
    obj.times.locationChanged.upgrade();

    if (obj is KdbxEntry) {
      obj.history.forEach(upgradeAllObjectTimesV4);
    }
  }

  /// Merges the given file into this file.
  /// Both files must have the same origin (ie. same root group UUID).
  MergeContext merge(KdbxFile other) {
    if (header.version < other.header.version) {
      throw KdbxUnsupportedException(
          'Kdbx version of source is newer. Upgrade file version before attempting to merge.');
    }
    if (other.body.rootGroup.uuid != body.rootGroup.uuid) {
      throw KdbxUnsupportedException(
          'Root groups of source and dest file do not match.');
    }

    if (other.body.meta.masterKeyChanged.isAfter(body.meta.masterKeyChanged)) {
      _credentials = other.credentials;
      header.writeKdfParameters(other.header.readKdfParameters);
      _logger.finest('Changing MasterKey and KDF params.');
    }
    final ctx = body.merge(other.body);
    // It's important that the merge operation above does not assume that the recycle
    // bin UUID points to a valid group but once the entire merge is complete, we
    // can safely clear the cache so that if it has been changed remotely, we reflect
    // that in this file before the overall merge procedure is complete.
    invalidateCachedValues();
    return ctx;
  }

  /// Imports the given file into this file.
  void import(KdbxFile other) {
    return body.import(other.body);
  }

  void invalidateCachedValues() {
    _recycleBin = null;
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
