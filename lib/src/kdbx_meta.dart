import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:quiver/iterables.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart' as xml;
import 'package:xml/xml.dart';

import 'package:kdbx/src/internal/extension_utils.dart';
import 'package:kdbx/src/kdbx_binary.dart';
import 'package:kdbx/src/kdbx_custom_data.dart';
import 'package:kdbx/src/kdbx_entry.dart';
import 'package:kdbx/src/kdbx_format.dart';
import 'package:kdbx/src/kdbx_header.dart';
import 'package:kdbx/src/kdbx_object.dart';
import 'package:kdbx/src/kdbx_xml.dart';

final _logger = Logger('kdbx_meta');

class KdbxMeta extends KdbxNode implements KdbxNodeContext {
  KdbxMeta.create({
    @required String databaseName,
    @required this.ctx,
    String generator,
  })  : customData = KdbxCustomData.create(),
        binaries = [],
        _customIcons = {},
        super.create('Meta') {
    this.databaseName.set(databaseName);
    databaseDescription.set(null, force: true);
    defaultUserName.set(null, force: true);
    this.generator.set(generator ?? 'kdbx.dart');
    settingsChanged.setToNow();
    masterKeyChanged.setToNow();
    recycleBinChanged.setToNow();
    historyMaxItems.set(Consts.DefaultHistoryMaxItems);
    historyMaxSize.set(Consts.DefaultHistoryMaxSize);
  }

  KdbxMeta.read(xml.XmlElement node, this.ctx)
      : customData = node
                .singleElement('CustomData')
                ?.let((e) => KdbxCustomData.read(e)) ??
            KdbxCustomData.create(),
        binaries = node
            .singleElement(KdbxXml.NODE_BINARIES)
            ?.let((el) sync* {
              for (final binaryNode in el.findElements(KdbxXml.NODE_BINARY)) {
                final id = int.parse(binaryNode.getAttribute(KdbxXml.ATTR_ID));
                yield MapEntry(
                  id,
                  KdbxBinary.readBinaryXml(binaryNode, isInline: false),
                );
              }
            })
            ?.toList()
            ?.let((binaries) {
              binaries.sort((a, b) => a.key.compareTo(b.key));
              for (var i = 0; i < binaries.length; i++) {
                if (i != binaries[i].key) {
                  throw KdbxCorruptedFileException(
                      'Invalid ID for binary. expected $i,'
                      ' but was ${binaries[i].key}');
                }
              }
              return binaries.map((e) => e.value).toList();
            }),
        _customIcons = node
                .singleElement(KdbxXml.NODE_CUSTOM_ICONS)
                ?.let((el) sync* {
                  for (final iconNode in el.findElements(KdbxXml.NODE_ICON)) {
                    yield KdbxCustomIcon(
                        uuid: KdbxUuid(
                            iconNode.singleTextNode(KdbxXml.NODE_UUID)),
                        data: base64.decode(
                            iconNode.singleTextNode(KdbxXml.NODE_DATA)));
                  }
                })
                ?.map((e) => MapEntry(e.uuid, e))
                ?.let((that) => Map.fromEntries(that)) ??
            {},
        super.read(node);

  @override
  final KdbxReadWriteContext ctx;

  final KdbxCustomData customData;

  /// only used in Kdbx 3
  final List<KdbxBinary> binaries;

  final Map<KdbxUuid, KdbxCustomIcon> _customIcons;

  Map<KdbxUuid, KdbxCustomIcon> get customIcons =>
      UnmodifiableMapView(_customIcons);

  void addCustomIcon(KdbxCustomIcon customIcon) {
    if (_customIcons.containsKey(customIcon.uuid)) {
      return;
    }
    modify(() => _customIcons[customIcon.uuid] = customIcon);
  }

  StringNode get generator => StringNode(this, 'Generator');

  StringNode get databaseName => StringNode(this, 'DatabaseName')
    ..setOnModifyListener(() => databaseNameChanged.setToNow());
  DateTimeUtcNode get databaseNameChanged =>
      DateTimeUtcNode(this, 'DatabaseNameChanged');

  StringNode get databaseDescription => StringNode(this, 'DatabaseDescription')
    ..setOnModifyListener(() => databaseDescriptionChanged.setToNow());
  DateTimeUtcNode get databaseDescriptionChanged =>
      DateTimeUtcNode(this, 'DatabaseDescriptionChanged');

  StringNode get defaultUserName => StringNode(this, 'DefaultUserName')
    ..setOnModifyListener(() => defaultUserNameChanged.setToNow());
  DateTimeUtcNode get defaultUserNameChanged =>
      DateTimeUtcNode(this, 'DefaultUserNameChanged');

  DateTimeUtcNode get masterKeyChanged =>
      DateTimeUtcNode(this, 'MasterKeyChanged');

  Base64Node get headerHash => Base64Node(this, 'HeaderHash');

  NullableBooleanNode get recycleBinEnabled =>
      NullableBooleanNode(this, 'RecycleBinEnabled');

  UuidNode get recycleBinUUID => UuidNode(this, 'RecycleBinUUID')
    ..setOnModifyListener(() => recycleBinChanged.setToNow());

  DateTimeUtcNode get settingsChanged =>
      DateTimeUtcNode(this, 'SettingsChanged');

  DateTimeUtcNode get recycleBinChanged =>
      DateTimeUtcNode(this, 'RecycleBinChanged');

  UuidNode get entryTemplatesGroup => UuidNode(this, 'EntryTemplatesGroup')
    ..setOnModifyListener(() => entryTemplatesGroupChanged.setToNow());
  DateTimeUtcNode get entryTemplatesGroupChanged =>
      DateTimeUtcNode(this, 'EntryTemplatesGroupChanged');

  IntNode get historyMaxItems => IntNode(this, 'HistoryMaxItems');

  /// max size of history in bytes.
  IntNode get historyMaxSize => IntNode(this, 'HistoryMaxSize');

  /// not sure what this node is supposed to do actually.
  IntNode get maintenanceHistoryDays => IntNode(this, 'MaintenanceHistoryDays');

//  void addCustomIcon

  BrowserDbSettings _browserSettings;
  BrowserDbSettings get browserSettings {
    if (_browserSettings == null) {
      final tempJson = customData['KeePassRPC.Config'];

      if (tempJson != null) {
        _browserSettings = BrowserDbSettings.fromJson(tempJson);
      } else {
        _browserSettings = BrowserDbSettings();
      }
    }
    return _browserSettings;
  }

  set browserSettings(BrowserDbSettings settings) {
    customData['KeePassRPC.Config'] = settings.toJson();
  }

  KeeVaultEmbeddedConfig _keeVaultSettings;
  KeeVaultEmbeddedConfig get keeVaultSettings {
    if (_keeVaultSettings == null) {
      final tempJson = customData['KeeVault.Config'];

      if (tempJson != null) {
        _keeVaultSettings = KeeVaultEmbeddedConfig.fromJson(tempJson);
      } else {
        _keeVaultSettings = KeeVaultEmbeddedConfig();
      }
    }
    return _keeVaultSettings;
  }

  set keeVaultSettings(KeeVaultEmbeddedConfig settings) {
    customData['KeeVault.Config'] = settings.toJson();
  }

  @override
  xml.XmlElement toXml() {
    final ret = super.toXml()..replaceSingle(customData.toXml());
    XmlUtils.removeChildrenByName(ret, KdbxXml.NODE_BINARIES);
    // with kdbx >= 4 we assume the binaries were already written in the header.
    if (ctx.versionMajor < 4) {
      ret.children.add(
        XmlElement(XmlName(KdbxXml.NODE_BINARIES))
          ..children.addAll(
            enumerate(ctx.binariesIterable).map((indexed) {
              final xmlBinary = XmlUtils.createNode(KdbxXml.NODE_BINARY)
                ..addAttribute(KdbxXml.ATTR_ID, indexed.index.toString());
              indexed.value.saveToXml(xmlBinary);
              return xmlBinary;
            }),
          ),
      );
    }
    XmlUtils.removeChildrenByName(ret, KdbxXml.NODE_CUSTOM_ICONS);
    ret.children.add(
      XmlElement(XmlName(KdbxXml.NODE_CUSTOM_ICONS))
        ..children.addAll(customIcons.values.map(
          (customIcon) => XmlUtils.createNode(KdbxXml.NODE_ICON, [
            XmlUtils.createTextNode(KdbxXml.NODE_UUID, customIcon.uuid.uuid),
            XmlUtils.createTextNode(
                KdbxXml.NODE_DATA, base64.encode(customIcon.data))
          ]),
        )),
    );
    return ret;
  }

  // Merge in changes in [other] into this meta data.
  void merge(KdbxMeta other, MergeContext ctx) {
    if (other.databaseNameChanged.isAfter(databaseNameChanged)) {
      databaseName.set(other.databaseName.get());
      databaseNameChanged.set(other.databaseNameChanged.get());
    }
    if (other.databaseDescriptionChanged.isAfter(databaseDescriptionChanged)) {
      databaseDescription.set(other.databaseDescription.get());
      databaseDescriptionChanged.set(other.databaseDescriptionChanged.get());
    }
    if (other.defaultUserNameChanged.isAfter(defaultUserNameChanged)) {
      defaultUserName.set(other.defaultUserName.get());
      defaultUserNameChanged.set(other.defaultUserNameChanged.get());
    }
    if (other.masterKeyChanged.isAfter(masterKeyChanged)) {
      masterKeyChanged.set(other.masterKeyChanged.get());
      _logger.info('MasterKey was changed.');
    }
    if (other.recycleBinChanged.isAfter(recycleBinChanged)) {
      recycleBinEnabled.set(other.recycleBinEnabled.get());
      recycleBinUUID.set(other.recycleBinUUID.get());
      recycleBinChanged.set(other.recycleBinChanged.get());
    }
    final otherIsNewer = other.settingsChanged.isAfter(settingsChanged);

    // merge custom data
    for (final otherCustomDataEntry in other.customData.entries) {
      if ((otherIsNewer || !customData.containsKey(otherCustomDataEntry.key)) &&
          !ctx.deletedObjects.containsKey(otherCustomDataEntry.key)) {
        customData[otherCustomDataEntry.key] = otherCustomDataEntry.value;
      }
    }

    // merge custom icons
    // Unused icons will be cleaned up later
    for (final otherCustomIcon in other._customIcons.values) {
      _customIcons[otherCustomIcon.uuid] ??= otherCustomIcon;
    }

    if (other.entryTemplatesGroupChanged.isAfter(entryTemplatesGroupChanged)) {
      entryTemplatesGroup.set(other.entryTemplatesGroup.get());
      entryTemplatesGroupChanged.set(other.entryTemplatesGroupChanged.get());
    }

    if (otherIsNewer) {
      historyMaxItems.set(other.historyMaxItems.get());
      historyMaxItems.set(other.historyMaxSize.get());
      historyMaxItems.set(other.maintenanceHistoryDays.get());
      //TODO: keyChangeRec and keyChangeForce and color
    }

    // Remove the cached versions of these so they have to be regenerated from the latest JSON when next requested
    _browserSettings = null;
    _keeVaultSettings = null;

    settingsChanged.set(other.settingsChanged.get());
  }
}

class KeeVaultEmbeddedConfig {
  KeeVaultEmbeddedConfig({
    this.version = 1,
    String randomId,
    this.addon,
    this.vault,
  }) : randomId = randomId ?? const Uuid().v4();

  factory KeeVaultEmbeddedConfig.fromMap(Map<String, dynamic> map) {
    if (map == null) {
      return KeeVaultEmbeddedConfig();
    }

    return KeeVaultEmbeddedConfig(
      version: map['version'] as int ?? 1,
      randomId: map['randomId'] as String,
      addon: Map<String, dynamic>.from(map['addon'] as Map<String, dynamic>),
      vault: Map<String, dynamic>.from(map['vault'] as Map<String, dynamic>),
    );
  }

  factory KeeVaultEmbeddedConfig.fromJson(String source) =>
      KeeVaultEmbeddedConfig.fromMap(
          json.decode(source) as Map<String, dynamic>);

  int /*!*/ version;
  String randomId;
  Map<String, dynamic> addon; // { "prefs": {}, "version": -1 };
  Map<String, dynamic> vault; // { prefs: {} },

  KeeVaultEmbeddedConfig copyWith({
    int version,
    String randomId,
    Map<String, dynamic> addon,
    Map<String, dynamic> vault,
  }) {
    return KeeVaultEmbeddedConfig(
      version: version ?? this.version,
      randomId: randomId ?? this.randomId,
      addon: addon ?? this.addon,
      vault: vault ?? this.vault,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'version': version,
      'randomId': randomId,
      'addon': addon,
      'vault': vault,
    };
  }

  String toJson() => json.encode(toMap());
  @override
  String toString() {
    return 'KeeVaultEmbeddedConfig(version: $version, randomId: $randomId, addon: $addon, vault: $vault)';
  }

  @override
  bool operator ==(Object o) {
    if (identical(this, o)) {
      return true;
    }

    final unOrdDeepEq = const DeepCollectionEquality.unordered().equals;
    return o is KeeVaultEmbeddedConfig &&
        o.version == version &&
        o.randomId == randomId &&
        unOrdDeepEq(o.addon, addon) &&
        unOrdDeepEq(o.vault, vault);
  }

  @override
  int get hashCode {
    return version.hashCode ^
        randomId.hashCode ^
        addon.hashCode ^
        vault.hashCode;
  }

//TODO: Move to keevault repo and implement
  //     settingsToSync: ['theme', 'locale', 'expandGroups', 'clipboardSeconds', 'autoSave',
  // 'rememberKeyFiles', 'idleMinutes', 'colorfulIcons', 'lockOnCopy', 'helpTipCopyShown',
  // 'templateHelpShown', 'hideEmptyFields', 'generatorPresets'],

  // this.settingsToSync.forEach(setting => {
  //     this.listenTo(AppSettingsModel.instance, 'change:' + setting, (obj) => {
  //         this.updateSetting('vault', setting, obj.changed[setting]);
  //     });
  // });
}

class BrowserDbSettings {
  BrowserDbSettings({
    this.version = 3,
    this.rootUUID,
    this.defaultMatchAccuracy = MatchAccuracy.Domain,
    this.defaultPlaceholderHandling = 'Default',
    this.displayPriorityField = false,
    this.displayGlobalPlaceholderOption = false,
    Map<String, String> matchedURLAccuracyOverrides,
  }) : matchedURLAccuracyOverrides =
            matchedURLAccuracyOverrides ?? <String, String>{};

  factory BrowserDbSettings.fromMap(Map<String, dynamic> map) {
    if (map == null) {
      return BrowserDbSettings();
    }

    return BrowserDbSettings(
        version: map['version'] as int ?? 3,
        rootUUID: map['rootUUID'] as String,
        defaultMatchAccuracy: MatchAccuracy.values.singleWhereOrNull(
                (val) => val == map['defaultMatchAccuracy']) ??
            MatchAccuracy.Domain,
        defaultPlaceholderHandling:
            map['defaultPlaceholderHandling'] as String ?? 'Default',
        displayPriorityField: map['displayPriorityField'] as bool ?? false,
        displayGlobalPlaceholderOption:
            map['displayGlobalPlaceholderOption'] as bool ?? false,
        matchedURLAccuracyOverrides:
            (map['matchedURLAccuracyOverrides'] as Map<String, dynamic>)
                    ?.cast<String, String>() ??
                <String, String>{});
  }

  factory BrowserDbSettings.fromJson(String source) =>
      BrowserDbSettings.fromMap(json.decode(source) as Map<String, dynamic>);

  int version;
  String rootUUID;
  // enum
  MatchAccuracy defaultMatchAccuracy;
  String defaultPlaceholderHandling;
  bool displayPriorityField;
  bool displayGlobalPlaceholderOption;
  Map<String, String> matchedURLAccuracyOverrides;

  BrowserDbSettings copyWith({
    int version,
    String rootUUID,
    MatchAccuracy defaultMatchAccuracy,
    String defaultPlaceholderHandling,
    bool displayPriorityField,
    bool displayGlobalPlaceholderOption,
    Map<String, String> matchedURLAccuracyOverrides,
  }) {
    return BrowserDbSettings(
      version: version ?? this.version,
      rootUUID: rootUUID ?? this.rootUUID,
      defaultMatchAccuracy: defaultMatchAccuracy ?? this.defaultMatchAccuracy,
      defaultPlaceholderHandling:
          defaultPlaceholderHandling ?? this.defaultPlaceholderHandling,
      displayPriorityField: displayPriorityField ?? this.displayPriorityField,
      displayGlobalPlaceholderOption:
          displayGlobalPlaceholderOption ?? this.displayGlobalPlaceholderOption,
      matchedURLAccuracyOverrides:
          matchedURLAccuracyOverrides ?? this.matchedURLAccuracyOverrides,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'version': version,
      'rootUUID': rootUUID,
      'defaultMatchAccuracy': defaultMatchAccuracy,
      'defaultPlaceholderHandling': defaultPlaceholderHandling,
      'displayPriorityField': displayPriorityField,
      'displayGlobalPlaceholderOption': displayGlobalPlaceholderOption,
      'matchedURLAccuracyOverrides': matchedURLAccuracyOverrides,
    };
  }

  String toJson() => json.encode(toMap());

  @override
  String toString() {
    return 'BrowserDbSettings(version: $version, rootUUID: $rootUUID, defaultMatchAccuracy: $defaultMatchAccuracy, defaultPlaceholderHandling: $defaultPlaceholderHandling, displayPriorityField: $displayPriorityField, displayGlobalPlaceholderOption: $displayGlobalPlaceholderOption), matchedURLAccuracyOverrides: $matchedURLAccuracyOverrides';
  }

  @override
  // ignore: avoid_renaming_method_parameters
  bool operator ==(Object o) {
    if (identical(this, o)) {
      return true;
    }

    final unOrdDeepEq = const DeepCollectionEquality.unordered().equals;
    return o is BrowserDbSettings &&
        o.version == version &&
        o.rootUUID == rootUUID &&
        o.defaultMatchAccuracy == defaultMatchAccuracy &&
        o.defaultPlaceholderHandling == defaultPlaceholderHandling &&
        o.displayPriorityField == displayPriorityField &&
        o.displayGlobalPlaceholderOption == displayGlobalPlaceholderOption &&
        unOrdDeepEq(o.matchedURLAccuracyOverrides, matchedURLAccuracyOverrides);
  }

  @override
  int get hashCode {
    return version.hashCode ^
        rootUUID.hashCode ^
        defaultMatchAccuracy.hashCode ^
        defaultPlaceholderHandling.hashCode ^
        displayPriorityField.hashCode ^
        displayGlobalPlaceholderOption.hashCode ^
        matchedURLAccuracyOverrides.hashCode;
  }
}

class KdbxCustomIcon {
  KdbxCustomIcon({/*required*/ this.uuid, /*required*/ this.data});

  /// uuid of the icon, must be unique within each file.
  final KdbxUuid uuid;

  /// Encoded png data of the image. will be base64 encoded into the kdbx file.
  final Uint8List data;
}
