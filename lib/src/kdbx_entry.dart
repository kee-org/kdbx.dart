import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
import 'package:collection/collection.dart';
import 'package:kdbx/src/crypto/protected_value.dart';
import 'package:kdbx/src/internal/extension_utils.dart';
import 'package:kdbx/src/kdbx_binary.dart';
import 'package:kdbx/src/kdbx_consts.dart';
import 'package:kdbx/src/kdbx_file.dart';
import 'package:kdbx/src/kdbx_format.dart';
import 'package:kdbx/src/kdbx_group.dart';
import 'package:kdbx/src/kdbx_header.dart';
import 'package:kdbx/src/kdbx_object.dart';
import 'package:kdbx/src/kdbx_xml.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:quiver/check.dart';
import 'package:xml/xml.dart';
import '../kdbx.dart';
import 'field.dart';

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

class BrowserEntrySettings {
  BrowserEntrySettings({
    this.version = 1,
    this.behaviour = BrowserAutoFillBehaviour.Default,
    required this.minimumMatchAccuracy,
    this.priority = 0,
    this.hide = false,
    this.realm = '',
    List<Pattern>? includeUrls,
    List<Pattern>? excludeUrls,
    List<BrowserFieldModel>? fields,
  })  : includeUrls = includeUrls ?? [],
        excludeUrls = excludeUrls ?? [],
        fields = fields ?? [];

  factory BrowserEntrySettings.fromMap(Map<String, dynamic>? map,
      {required MatchAccuracy minimumMatchAccuracy}) {
    if (map == null) {
      return BrowserEntrySettings(minimumMatchAccuracy: minimumMatchAccuracy);
    }

    return BrowserEntrySettings(
      version: map['version'] as int? ?? 1,
      behaviour: getBehaviour(map),
      minimumMatchAccuracy: getMam(map),
      priority: map['priority'] as int? ?? 0,
      hide: map['hide'] as bool? ?? false,
      realm: map['hTTPRealm'] as String?,
      includeUrls: getIncludeUrls(map),
      excludeUrls: getExcludeUrls(map),
      fields: List<BrowserFieldModel>.from((map['formFieldList']
                  as List<dynamic>?)
              ?.cast<Map<String, dynamic>>()
              .map<BrowserFieldModel>((x) => BrowserFieldModel.fromMap(x)) ??
          <BrowserFieldModel>[]),
    );
  }

  factory BrowserEntrySettings.fromJson(String source,
          {required MatchAccuracy minimumMatchAccuracy}) =>
      BrowserEntrySettings.fromMap(json.decode(source) as Map<String, dynamic>?,
          minimumMatchAccuracy: minimumMatchAccuracy);

  int version;
  // enum
  BrowserAutoFillBehaviour behaviour;
  // enum
  MatchAccuracy minimumMatchAccuracy;
  int priority; // always 0
  bool hide;
  String? realm;
  List<Pattern> includeUrls;
  List<Pattern> excludeUrls;
  List<BrowserFieldModel> fields;

  BrowserEntrySettings copyWith({
    int? version,
    BrowserAutoFillBehaviour? behaviour,
    MatchAccuracy? minimumMatchAccuracy,
    int? priority,
    bool? hide,
    String? realm,
    List<Pattern>? includeUrls,
    List<Pattern>? excludeUrls,
    List<BrowserFieldModel>? fields,
  }) {
    return BrowserEntrySettings(
      version: version ?? this.version,
      behaviour: behaviour ?? this.behaviour,
      minimumMatchAccuracy: minimumMatchAccuracy ?? this.minimumMatchAccuracy,
      priority: priority ?? this.priority,
      hide: hide ?? this.hide,
      realm: realm ?? this.realm,
      includeUrls: includeUrls ?? this.includeUrls,
      excludeUrls: excludeUrls ?? this.excludeUrls,
      fields: fields ?? this.fields,
    );
  }

  static BrowserAutoFillBehaviour getBehaviour(Map<String, dynamic> map) {
    if (map['neverAutoFill'] as bool? ?? false) {
      return BrowserAutoFillBehaviour.NeverAutoFillNeverAutoSubmit;
    } else if (map['alwaysAutoSubmit'] as bool? ?? false) {
      return BrowserAutoFillBehaviour.AlwaysAutoFillAlwaysAutoSubmit;
    } else if ((map['alwaysAutoFill'] as bool? ?? false) &&
        (map['neverAutoSubmit'] as bool? ?? false)) {
      return BrowserAutoFillBehaviour.AlwaysAutoFillNeverAutoSubmit;
    } else if (map['neverAutoSubmit'] as bool? ?? false) {
      return BrowserAutoFillBehaviour.NeverAutoSubmit;
    } else if (map['alwaysAutoFill'] as bool? ?? false) {
      return BrowserAutoFillBehaviour.AlwaysAutoFill;
    } else {
      return BrowserAutoFillBehaviour.Default;
    }
  }

  static MatchAccuracy getMam(Map<String, dynamic> map) {
    if (map['blockHostnameOnlyMatch'] as bool? ?? false) {
      return MatchAccuracy.Exact;
    } else if (map['blockDomainOnlyMatch'] as bool? ?? false) {
      return MatchAccuracy.Hostname;
    } else {
      return MatchAccuracy.Domain;
    }
  }

  static Map<String, bool> parseBehaviour(BrowserAutoFillBehaviour behaviour) {
    switch (behaviour) {
      case BrowserAutoFillBehaviour.AlwaysAutoFill:
        return {
          'alwaysAutoFill': true,
          'alwaysAutoSubmit': false,
          'neverAutoFill': false,
          'neverAutoSubmit': false,
        };
      case BrowserAutoFillBehaviour.NeverAutoSubmit:
        return {
          'alwaysAutoFill': false,
          'alwaysAutoSubmit': false,
          'neverAutoFill': false,
          'neverAutoSubmit': true,
        };
      case BrowserAutoFillBehaviour.AlwaysAutoFillAlwaysAutoSubmit:
        return {
          'alwaysAutoFill': true,
          'alwaysAutoSubmit': true,
          'neverAutoFill': false,
          'neverAutoSubmit': false,
        };
      case BrowserAutoFillBehaviour.NeverAutoFillNeverAutoSubmit:
        return {
          'alwaysAutoFill': false,
          'alwaysAutoSubmit': false,
          'neverAutoFill': true,
          'neverAutoSubmit': true,
        };
      case BrowserAutoFillBehaviour.AlwaysAutoFillNeverAutoSubmit:
        return {
          'alwaysAutoFill': true,
          'alwaysAutoSubmit': false,
          'neverAutoFill': false,
          'neverAutoSubmit': true,
        };
      case BrowserAutoFillBehaviour.Default:
        return {
          'alwaysAutoFill': false,
          'alwaysAutoSubmit': false,
          'neverAutoFill': false,
          'neverAutoSubmit': false,
        };
    }
  }

  static Map<String, bool> parseMam(MatchAccuracy mam) {
    switch (mam) {
      case MatchAccuracy.Domain:
        return {
          'blockDomainOnlyMatch': false,
          'blockHostnameOnlyMatch': false,
        };
      case MatchAccuracy.Hostname:
        return {
          'blockDomainOnlyMatch': true,
          'blockHostnameOnlyMatch': false,
        };
      default:
        return {
          'blockDomainOnlyMatch': false,
          'blockHostnameOnlyMatch': true,
        };
    }
  }

  static Map<String, List<String>> parseUrls(
      List<Pattern> includeUrls, List<Pattern> excludeUrls) {
    final altURLs = <String>[];
    final regExURLs = <String>[];
    final blockedURLs = <String>[];
    final regExBlockedURLs = <String>[];
    for (var p in includeUrls) {
      if (p is RegExp) {
        regExURLs.add(p.pattern);
      } else if (p is String) {
        altURLs.add(p);
      }
    }
    for (var p in excludeUrls) {
      if (p is RegExp) {
        regExBlockedURLs.add(p.pattern);
      } else if (p is String) {
        blockedURLs.add(p);
      }
    }
    return <String, List<String>>{
      'altURLs': altURLs,
      'regExURLs': regExURLs,
      'blockedURLs': blockedURLs,
      'regExBlockedURLs': regExBlockedURLs,
    };
  }

  static List<Pattern> getIncludeUrls(Map<String, dynamic> map) {
    final includeUrls = <Pattern>[];
    final altUrls = (map['altURLs'] as List<dynamic>?)?.cast<String>();
    final regExURLs = (map['regExURLs'] as List<dynamic>?)?.cast<String>();
    if (altUrls != null && altUrls is List<String>) {
      altUrls.forEach(includeUrls.add);
    }
    if (regExURLs != null && regExURLs is List<String>) {
      for (var url in regExURLs) {
        includeUrls.add(RegExp(url));
      }
    }
    return includeUrls;
  }

  static List<Pattern> getExcludeUrls(Map<String, dynamic> map) {
    final excludeUrls = <Pattern>[];
    final blockedURLs = (map['blockedURLs'] as List<dynamic>?)?.cast<String>();
    final regExBlockedURLs =
        (map['regExBlockedURLs'] as List<dynamic>?)?.cast<String>();
    if (blockedURLs != null && blockedURLs is List<String>) {
      blockedURLs.forEach(excludeUrls.add);
    }
    if (regExBlockedURLs != null && regExBlockedURLs is List<String>) {
      for (var url in regExBlockedURLs) {
        excludeUrls.add(RegExp(url));
      }
    }
    return excludeUrls;
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'version': version,
      'priority': priority,
      'hide': hide,
      'hTTPRealm': realm,
      'formFieldList': fields.map((x) => x.toMap()).toList(),
      ...parseBehaviour(behaviour),
      ...parseMam(minimumMatchAccuracy),
      ...parseUrls(includeUrls, excludeUrls),
    };
  }

  String toJson() => json.encode(toMap());

  @override
  String toString() {
    return 'BrowserSettingsModel(version: $version, behaviour: $behaviour, minimumMatchAccuracy: $minimumMatchAccuracy, priority: $priority, hide: $hide, realm: $realm, includeUrls: $includeUrls, excludeUrls: $excludeUrls, fields: $fields)';
  }

  @override
  // ignore: avoid_renaming_method_parameters
  bool operator ==(Object o) {
    if (identical(this, o)) {
      return true;
    }
    final unOrdDeepEq = const DeepCollectionEquality.unordered().equals;
    return o is BrowserEntrySettings &&
        o.version == version &&
        o.behaviour == behaviour &&
        o.minimumMatchAccuracy == minimumMatchAccuracy &&
        o.priority == priority &&
        o.hide == hide &&
        o.realm == realm &&
        unOrdDeepEq(o.includeUrls, includeUrls) &&
        unOrdDeepEq(o.excludeUrls, excludeUrls) &&
        unOrdDeepEq(o.fields, fields);
  }

  @override
  int get hashCode {
    return version.hashCode ^
        behaviour.hashCode ^
        minimumMatchAccuracy.hashCode ^
        priority.hashCode ^
        hide.hashCode ^
        realm.hashCode ^
        includeUrls.hashCode ^
        excludeUrls.hashCode ^
        fields.hashCode;
  }
}

enum BrowserAutoFillBehaviour {
  Default,
  AlwaysAutoFill,
  NeverAutoSubmit,
  AlwaysAutoFillNeverAutoSubmit,
  AlwaysAutoFillAlwaysAutoSubmit,
  NeverAutoFillNeverAutoSubmit
}

enum MatchAccuracy { Exact, Hostname, Domain }

extension KdbxEntryInternal on KdbxEntry {
  KdbxEntry cloneInto(KdbxGroup otherGroup, {bool toHistoryEntry = false}) =>
      KdbxEntry.create(
        otherGroup.file!,
        otherGroup,
        isHistoryEntry: toHistoryEntry,
      )
        ..forceSetUuid(uuid)
        ..let(toHistoryEntry ? (x) => null : otherGroup.addEntry)
        .._overwriteFrom(
          OverwriteContext.noop,
          this,
          includeHistory: !toHistoryEntry,
        );

  List<KdbxSubNode> get _overwriteNodes => [
        ...objectNodes,
        foregroundColor,
        backgroundColor,
        overrideURL,
        tags,
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
    assertSameUuid(other, 'overwrite');
    overwriteSubNodesFrom(
      overwriteContext,
      _overwriteNodes,
      other._overwriteNodes,
    );
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
  })  : customData = KdbxCustomData.create(),
        history = [],
        super.create(file.ctx, file, 'Entry', parent) {
    icon.set(KdbxIcon.Key);
    _browserSettings = BrowserEntrySettings(
        minimumMatchAccuracy:
            file.body.meta.browserSettings.defaultMatchAccuracy);
  }

  @override
  KdbxGroup get parent => super.parent!;

  KdbxEntry.read(KdbxReadWriteContext ctx, KdbxGroup? parent, XmlElement node,
      {this.isHistoryEntry = false})
      : customData = node
                .singleElement('CustomData')
                ?.let((e) => KdbxCustomData.read(e)) ??
            KdbxCustomData.create(),
        history = [],
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
      final tempJson = stringEntries
          .firstWhereOrNull((s) => s.key.key == 'KPRPC JSON')
          ?.value;

      if (tempJson != null) {
        _browserSettings = BrowserEntrySettings.fromJson(tempJson.getText(),
            minimumMatchAccuracy:
                file!.body.meta.browserSettings.defaultMatchAccuracy);
      } else {
        _browserSettings = BrowserEntrySettings(
            minimumMatchAccuracy:
                file!.body.meta.browserSettings.defaultMatchAccuracy);
      }
    }
    return _browserSettings!;
  }

  set browserSettings(BrowserEntrySettings settings) {
    setString(
        KdbxKey('KPRPC JSON'), ProtectedValue.fromString(settings.toJson()));
    _browserSettings = null;
  }

  final KdbxCustomData customData;

  final bool isHistoryEntry;

  final List<KdbxEntry> history;

  ColorNode get foregroundColor => ColorNode(this, 'ForegroundColor');
  ColorNode get backgroundColor => ColorNode(this, 'BackgroundColor');
  StringNode get overrideURL => StringNode(this, 'OverrideURL');
  StringListNode get tags => StringListNode(this, 'Tags');

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
    browserSettings.hide = false;
    browserSettings = browserSettings;
    return;
  }

  void addAndroidPackageName(String name) {
    if (!androidPackageNames.contains(name)) {
      androidPackageNames.add(name);
      androidPackageNames = androidPackageNames;
    }
    browserSettings.hide = false;
    browserSettings = browserSettings;
    return;
  }

  @override
  void onBeforeModify() {
    super.onBeforeModify();
    history.add(KdbxEntry.read(
      ctx,
      parent,
      toXml(),
      isHistoryEntry: true,
    )..file = file);
  }

  @override
  XmlElement toXml() {
    final el = super.toXml();
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

    for (var historyEntry in history) {
      dict[historyEntry.times.lastModificationTime.get()] = historyEntry;
    }

    for (var historyEntry in otherHistory) {
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
    return 'KdbxEntry{uuid=$uuid,'
        'name=${debugLabel()}}';
  }

  void revertToHistoryEntry(int index) {
    final requestedHistoryItem = history[index];
    modify(() => _overwriteFrom(OverwriteContext.noop, requestedHistoryItem));
  }
}
