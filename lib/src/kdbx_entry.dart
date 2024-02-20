import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:kdbx/src/internal/extension_utils.dart';
import 'package:kdbx/src/kdbx_format.dart';
import 'package:kdbx/src/kdbx_object.dart';
import 'package:kdbx/src/kdbx_xml.dart';
import 'package:kdbx/src/kee_vault_model/browser_entry_settings_v1.dart';
import 'package:kdbx/src/utils/guid_service.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:quiver/check.dart';
import 'package:xml/xml.dart';

import '../kdbx.dart';

final _logger = Logger('kdbx.kdbx_entry');

class KdbxKeyCommon {
  static const KEY_TITLE = 'Title';
  static const KEY_URL = 'URL';
  static const KEY_USER_NAME = 'UserName';
  static const KEY_PASSWORD = 'Password';
  static const KEY_OTP = 'otp';
  static const KEY_NOTES = 'Notes';

  static const KdbxKey TITLE = KdbxKey._(KEY_TITLE, 'title');
  static const KdbxKey URL = KdbxKey._(KEY_URL, 'url');
  static const KdbxKey USER_NAME = KdbxKey._(KEY_USER_NAME, 'username');
  static const KdbxKey PASSWORD = KdbxKey._(KEY_PASSWORD, 'password');
  static const KdbxKey OTP = KdbxKey._(KEY_OTP, 'otp');
  static const KdbxKey NOTES = KdbxKey._(KEY_NOTES, 'notes');

  static const List<KdbxKey> all = [
    TITLE,
    URL,
    USER_NAME,
    PASSWORD,
    OTP,
    NOTES,
  ];
}

// this is called during initialization of [KdbxFormat] to make sure there are
// no typos in the constant declared above.
bool kdbxKeyCommonAssertConsistency() {
  assert((() {
    for (final key in KdbxKeyCommon.all) {
      assert(key.key.toLowerCase() == key._canonicalKey);
    }
    return true;
  })());
  return true;
}

/// Represents a case insensitive (but case preserving) key.
class KdbxKey {
  KdbxKey(this.key) : _canonicalKey = key.toLowerCase();
  const KdbxKey._(this.key, this._canonicalKey);

  final String key;
  final String _canonicalKey;

  @override
  bool operator ==(Object other) =>
      other is KdbxKey && _canonicalKey == other._canonicalKey;

  @override
  int get hashCode => _canonicalKey.hashCode;

  @override
  String toString() {
    return 'KdbxKey{key: $key}';
  }
}

extension KdbxEntryInternal on KdbxEntry {
  KdbxEntry cloneInto(KdbxGroup otherGroup,
          {bool toHistoryEntry = false, bool withNewUuid = false}) =>
      KdbxEntry.create(
        otherGroup.file!,
        otherGroup,
        isHistoryEntry: toHistoryEntry,
      )
        ..forceSetUuid(withNewUuid ? KdbxUuid.random() : uuid)
        ..let(toHistoryEntry ? (x) => null : otherGroup.addEntry)
        .._overwriteFrom(
          OverwriteContext.noop,
          this,
          includeHistory: !toHistoryEntry,
        );

  List<KdbxSubNode<dynamic>> get _overwriteNodes => [
        ...objectNodes,
        foregroundColor,
        backgroundColor,
        overrideURL,
        qualityCheck,
      ];

  void _overwriteFrom(
    OverwriteContext overwriteContext,
    KdbxEntry other, {
    bool includeHistory = false,
  }) {
    // we only support overwriting history, if it is empty.
    // Throws exception if history is not empty and we have asked to include it
    checkArgument(!includeHistory || history.isEmpty,
        message:
            'We can only overwrite with history, if local history is empty.');
    overwriteSubNodesFrom(
      overwriteContext,
      _overwriteNodes,
      other._overwriteNodes,
    );
    // reset browserSettings for rebuild from potentially changed string
    _browserSettings = null;

    // overwrite all strings
    final stringsDiff = _diffMap(_strings, other._strings);
    if (stringsDiff.isNotEmpty) {
      overwriteContext.trackChange(this,
          node: 'strings', debug: 'changed: ${stringsDiff.join(',')}');
    }
    _strings.clear();
    _strings.addAll(other._strings);
    // overwrite all binaries
    final newBinaries = other._binaries.map((key, value) => MapEntry(
          key,
          ctx.findBinaryByValue(value) ??
              (value..let((that) => ctx.addBinary(that))),
        ));
    _binaries.clear();
    _binaries.addAll(newBinaries);
    // Dart doesn't know this is actually OK since it's an extension to a subclass
    // ignore: invalid_use_of_protected_member
    customData.overwriteFrom(other.customData);
    times.overwriteFrom(other.times);
    if (includeHistory) {
      for (final historyEntry in other.history) {
        history.add(historyEntry.cloneInto(parent, toHistoryEntry: true));
      }
    }
  }

  List<String> _diffMap(Map<Object, Object?> a, Map<Object, Object?> b) {
    final keys = {...a.keys, ...b.keys};
    final ret = <String>[];
    for (final key in keys) {
      if (a[key] != b[key]) {
        ret.add(key.toString());
      }
    }
    return ret;
  }
}

class KdbxEntry extends KdbxObject {
  /// Creates a new entry in the given parent group.
  /// callers are still responsible for calling [parent.addEntry(..)]!
  ///
  /// FIXME: this makes no sense, we should automatically attach this to the parent.
  KdbxEntry.create(
    KdbxFile file,
    KdbxGroup parent, {
    this.isHistoryEntry = false,
  })  : history = [],
        super.create(file.ctx, file, 'Entry', parent) {
    icon.set(KdbxIcon.Key);
    _browserSettings = BrowserEntrySettings(
      matcherConfigs: [
        EntryMatcherConfig.forDefaultUrlMatchBehaviour(
            file.body.meta.browserSettings.defaultMatchAccuracy)
      ],
    );
  }

  KdbxEntry.read(KdbxReadWriteContext ctx, KdbxGroup? parent, XmlElement node,
      {this.isHistoryEntry = false})
      : history = [],
        super.read(ctx, parent, node) {
    _strings.addEntries(node.findElements(KdbxXml.NODE_STRING).map((el) {
      final key = KdbxKey(el.findElements(KdbxXml.NODE_KEY).single.text);
      final valueNode = el.findElements(KdbxXml.NODE_VALUE).single;
      if (valueNode.getAttribute(KdbxXml.ATTR_PROTECTED)?.toLowerCase() ==
          'true') {
        return MapEntry(key, KdbxFile.protectedValueForNode(valueNode));
      } else {
        return MapEntry(key, PlainValue(valueNode.text));
      }
    }));
    _binaries.addEntries(node.findElements(KdbxXml.NODE_BINARY).map((el) {
      final key = KdbxKey(el.findElements(KdbxXml.NODE_KEY).single.text);
      final valueNode = el.findElements(KdbxXml.NODE_VALUE).single;
      final ref = valueNode.getAttribute(KdbxXml.ATTR_REF);
      if (ref != null) {
        final refId = int.parse(ref);
        final binary = ctx.binaryById(refId);
        if (binary == null) {
          throw KdbxCorruptedFileException(
              'Unable to find binary with id $refId');
        }
        return MapEntry(key, binary);
      }

      return MapEntry(key, KdbxBinary.readBinaryXml(valueNode, isInline: true));
    }));
    history.addAll(node
            .findElements(KdbxXml.NODE_HISTORY)
            .singleOrNull
            ?.findElements('Entry')
            .map((entry) =>
                KdbxEntry.read(ctx, parent, entry, isHistoryEntry: true))
            .toList() ??
        []);
  }

  @override
  KdbxGroup get parent => super.parent!;

  List<String> get androidPackageNames {
    final tempJson = customData['KeeVault.AndroidPackageNames'];

    if (tempJson != null) {
      return (json.decode(tempJson) as List<dynamic>).cast<String>();
    }

    return [];
  }

  set androidPackageNames(List<String> names) {
    customData['KeeVault.AndroidPackageNames'] = json.encode(names);
  }

  BrowserEntrySettings? _browserSettings;
  BrowserEntrySettings get browserSettings {
    if (_browserSettings == null) {
      final cdJson = getCustomData('KPRPC JSON');

      if (cdJson != null) {
        _browserSettings = BrowserEntrySettings.fromJson(cdJson,
            minimumMatchAccuracy:
                file!.body.meta.browserSettings.defaultMatchAccuracy);
      } else {
        final stringJson = stringEntries
            .firstWhereOrNull((s) => s.key.key == 'KPRPC JSON')
            ?.value
            ?.getText();

        if (stringJson != null) {
          final v1 = BrowserEntrySettingsV1.fromJson(stringJson,
              minimumMatchAccuracy:
                  file!.body.meta.browserSettings.defaultMatchAccuracy);
          _browserSettings = v1.convertToV2(GuidService());
        } else {
          _browserSettings = BrowserEntrySettings(
            matcherConfigs: [
              EntryMatcherConfig.forDefaultUrlMatchBehaviour(
                  file!.body.meta.browserSettings.defaultMatchAccuracy)
            ],
          );
        }
      }
    }
    return _browserSettings!;
  }

  set browserSettings(BrowserEntrySettings settings) {
    setCustomData('KPRPC JSON', settings.toJson());
    try {
      final v1 = settings.convertToV1();
      setString(KdbxKey('KPRPC JSON'), ProtectedValue.fromString(v1.toJson()));
    } catch (ex) {
      _logger.severe(
          'String KPRPC JSON failed to convert or write. This may indicate a newer version of Kee Vault was used to create this configuration.');
    }
    _browserSettings = null;
  }

  final bool isHistoryEntry;

  final List<KdbxEntry> history;

  ColorNode get foregroundColor =>
      ColorNode(this, KdbxXml.NODE_FOREGROUND_COLOR);
  ColorNode get backgroundColor =>
      ColorNode(this, KdbxXml.NODE_BACKGROUND_COLOR);
  StringNode get overrideURL => StringNode(this, KdbxXml.NODE_OVERRIDE_URL);
  NullableBooleanNode get qualityCheck =>
      NullableBooleanNode(this, KdbxXml.NODE_QUALITY_CHECK);

  @override
  set file(KdbxFile? file) {
    super.file = file;
    // TODO this looks like some weird workaround, get rid of the
    // `file` reference.
    for (final historyEntry in history) {
      historyEntry.file = file;
    }
  }

  void addAutofillUrl(String webDomain, String? scheme) {
    final newUrl = '${scheme ?? "http"}://$webDomain';
    final currentUrl = stringEntries
        .firstWhereOrNull((s) => s.key == KdbxKeyCommon.URL)
        ?.value
        ?.getText();
    final alreadyPresent =
        newUrl == currentUrl || browserSettings.includeUrls.contains(newUrl);
    if (!alreadyPresent) {
      if (currentUrl == null) {
        setString(KdbxKeyCommon.URL, PlainValue(newUrl));
      } else {
        browserSettings.includeUrls.add(newUrl);
      }
    }
    browserSettings.matcherConfigs
        .removeWhere((mc) => mc.matcherType == EntryMatcherType.Hide);
    browserSettings = browserSettings;
    return;
  }

  void addAndroidPackageName(String name) {
    if (!androidPackageNames.contains(name)) {
      final updatedList = androidPackageNames..add(name);
      androidPackageNames = updatedList;
    }
    browserSettings.matcherConfigs
        .removeWhere((mc) => mc.matcherType == EntryMatcherType.Hide);
    browserSettings = browserSettings;
    return;
  }

  @override
  void onBeforeFirstModify() {
    super.onBeforeFirstModify();
    history.add(KdbxEntry.read(
      ctx,
      parent,
      toXml(),
      isHistoryEntry: true,
    )..file = file);
  }

  @override
  XmlElement toXml() {
    final el = super.toXml()..replaceSingle(customData.toXml());

    if (ctx.version < KdbxVersion.V4_1) {
      XmlUtils.removeChildrenByName(el, KdbxXml.NODE_QUALITY_CHECK);
      XmlUtils.removeChildrenByName(el, KdbxXml.NODE_PREVIOUS_PARENT_GROUP);
    }

    XmlUtils.removeChildrenByName(el, KdbxXml.NODE_STRING);
    XmlUtils.removeChildrenByName(el, KdbxXml.NODE_HISTORY);
    XmlUtils.removeChildrenByName(el, KdbxXml.NODE_BINARY);
    el.children.addAll(stringEntries.map((stringEntry) {
      final value = XmlElement(XmlName(KdbxXml.NODE_VALUE));
      if (stringEntry.value is ProtectedValue) {
        value.attributes.add(
            XmlAttribute(XmlName(KdbxXml.ATTR_PROTECTED), KdbxXml.VALUE_TRUE));
        KdbxFile.setProtectedValueForNode(
            value, stringEntry.value as ProtectedValue);
      } else if (stringEntry.value is StringValue) {
        value.children.add(XmlText(stringEntry.value!.getText()));
      }
      return XmlElement(XmlName(KdbxXml.NODE_STRING))
        ..children.addAll([
          XmlElement(XmlName(KdbxXml.NODE_KEY))
            ..children.add(XmlText(stringEntry.key.key)),
          value,
        ]);
    }));
    el.children.addAll(binaryEntries.map((binaryEntry) {
      final key = binaryEntry.key;
      final binary = binaryEntry.value;
      final value = XmlElement(XmlName(KdbxXml.NODE_VALUE));
      if (binary.isInline) {
        binary.saveToXml(value);
      } else {
        final binaryIndex = ctx.findBinaryId(binary);
        value.addAttribute(KdbxXml.ATTR_REF, binaryIndex.toString());
      }
      return XmlElement(XmlName(KdbxXml.NODE_BINARY))
        ..children.addAll([
          XmlElement(XmlName(KdbxXml.NODE_KEY))..children.add(XmlText(key.key)),
          value,
        ]);
    }));
    if (!isHistoryEntry) {
      el.children.add(
        XmlElement(XmlName(KdbxXml.NODE_HISTORY))
          ..children.addAll(history.map((e) => e.toXml())),
      );
    }
    return el;
  }

  final Map<KdbxKey, StringValue?> _strings = {};

  final Map<KdbxKey, KdbxBinary> _binaries = {};

  Iterable<MapEntry<KdbxKey, KdbxBinary>> get binaryEntries =>
      _binaries.entries;

  KdbxBinary? getBinary(KdbxKey key) => _binaries[key];

//  Map<KdbxKey, StringValue> get strings => UnmodifiableMapView(_strings);

  Iterable<MapEntry<KdbxKey, StringValue?>> get stringEntries =>
      _strings.entries;

  StringValue? getString(KdbxKey key) => _strings[key];

  void setString(KdbxKey key, StringValue? value) {
    if (_strings[key] == value) {
      _logger.finest('Value did not change for $key');
      return;
    }
    modify(() {
      if (value == null) {
        _strings.remove(key);
      } else {
        _strings[key] = value;
      }
    });
  }

  void renameKey(KdbxKey oldKey, KdbxKey newKey) {
    final value = _strings[oldKey];
    removeString(oldKey);
    _strings[newKey] = value;
  }

  void removeString(KdbxKey key) => setString(key, null);

  String? _plainValue(KdbxKey key) {
    final value = _strings[key];
    if (value is PlainValue) {
      return value.getText();
    }
    return value?.toString();
  }

  String get label =>
      _plainValue(KdbxKeyCommon.TITLE)?.takeUnlessBlank() ??
      _plainValue(KdbxKeyCommon.URL)?.takeUnlessBlank() ??
      '';

  set label(String label) => setString(KdbxKeyCommon.TITLE, PlainValue(label));

  /// Creates a new binary and adds it to this entry.
  KdbxBinary createBinary({
    required bool isProtected,
    required String name,
    required Uint8List bytes,
  }) {
    // make sure we don't have a path, just the file name.
    final key = _uniqueBinaryName(path.basename(name));
    final binary = KdbxBinary(
      isInline: false,
      isProtected: isProtected,
      value: bytes,
    );
    modify(() {
      file!.ctx.addBinary(binary);
      _binaries[key] = binary;
    });
    return binary;
  }

  void removeBinary(KdbxKey binaryKey) {
    modify(() {
      final binary = _binaries.remove(binaryKey);
      if (binary == null) {
        throw StateError(
            'Trying to remove binary key $binaryKey does not exist.');
      }
      // binary will not be removed (yet) from file, because it will
      // be referenced in history.
    });
  }

  KdbxKey _uniqueBinaryName(String fileName) {
    final lastIndex = fileName.lastIndexOf('.');
    final baseName =
        lastIndex > -1 ? fileName.substring(0, lastIndex) : fileName;
    final ext = lastIndex > -1 ? fileName.substring(lastIndex + 1) : 'ext';
    for (var i = 0; i < 1000; i++) {
      final k = i == 0 ? KdbxKey(fileName) : KdbxKey('$baseName$i.$ext');
      if (!_binaries.containsKey(k)) {
        return k;
      }
    }
    throw StateError('Unable to find unique name for $fileName');
  }

  static KdbxEntry? _findHistoryEntry(
          List<KdbxEntry> history, DateTime? lastModificationTime) =>
      history.firstWhereOrNull((history) =>
          history.times.lastModificationTime.get() == lastModificationTime);

  @override
  void import(KdbxEntry other, Map<KdbxUuid, KdbxUuid> uuidMap) {
    return;
    //_overwriteFrom(OverwriteContext.noop, other, includeHistory: true);
  }

  @override
  void merge(MergeContext mergeContext, KdbxEntry other) {
    assertSameUuid(other, 'merge');
    if (other.wasModifiedAfter(this)) {
      _logger.finest('$this has incoming changes.');
      // other object is newer, create new history entry and copy fields.
      modify(() => _overwriteFrom(mergeContext, other),
          preserveModificationTime: true);
    } else if (wasModifiedAfter(other)) {
      _logger.finest('$this has outgoing changes.');
      // we are newer. check if the old revision lives on in our history.
      final theirLastModificationTime = other.times.lastModificationTime.get();
      final historyEntry =
          _findHistoryEntry(history, theirLastModificationTime);
      if (historyEntry == null) {
        // it seems like we don't know about that state, so we have to add
        // it to history.
        history.add(other.cloneInto(parent, toHistoryEntry: true));
      }
    } else {
      _logger.finest('$this has no changes.');
    }

    mergeEntryHistory(mergeContext, history, other.history);

    mergeContext.markAsMerged(this);
  }

  void mergeEntryHistory(MergeContext mergeContext, List<KdbxEntry> history,
      List<KdbxEntry> otherHistory) {
    final dict = SplayTreeMap<DateTime?, KdbxEntry>();

    for (final historyEntry in history) {
      dict[historyEntry.times.lastModificationTime.get()] = historyEntry;
    }

    for (final historyEntry in otherHistory) {
      final key = historyEntry.times.lastModificationTime.get();
      if (!dict.containsKey(key)) {
        dict[key] = historyEntry.cloneInto(parent, toHistoryEntry: true);
        mergeContext.trackChange(
          this,
          debug: 'merge in history '
              '$key',
        );
      }
    }

    history.clear();
    history.addAll(dict.values);
  }

  String debugLabel() =>
      label.takeUnlessBlank() ?? _plainValue(KdbxKeyCommon.USER_NAME) ?? '';

  @override
  String toString() {
    return 'KdbxEntry{uuid=$uuid}';
  }

  void revertToHistoryEntry(int index) {
    final requestedHistoryItem = history[index];
    modify(() => _overwriteFrom(OverwriteContext.noop, requestedHistoryItem));
  }
}
