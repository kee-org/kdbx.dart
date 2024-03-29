import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:collection/collection.dart';
import 'package:kdbx/src/internal/extension_utils.dart';
import 'package:kdbx/src/kdbx_binary.dart';
import 'package:kdbx/src/kdbx_custom_data.dart';
import 'package:kdbx/src/kdbx_exceptions.dart';
import 'package:kdbx/src/kdbx_format.dart';
import 'package:kdbx/src/kdbx_header.dart';
import 'package:kdbx/src/kdbx_object.dart';
import 'package:kdbx/src/kdbx_xml.dart';
import 'package:kdbx/src/kee_vault_model/enums.dart';
import 'package:logging/logging.dart';
import 'package:quiver/iterables.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart' as xml;
import 'package:xml/xml.dart';

final _logger = Logger('kdbx_meta');

class KdbxMeta extends KdbxNode implements KdbxNodeContext {
  KdbxMeta.create({
    required String databaseName,
    required this.ctx,
    String? generator,
  })  : customData = KdbxMetaCustomData.create(),
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

  KdbxMeta.read(super.node, this.ctx)
      : customData = node
                .singleElement(KdbxXml.NODE_CUSTOM_DATA)
                ?.let((e) => KdbxMetaCustomData.read(e)) ??
            KdbxMetaCustomData.create(),
        binaries = node
            .singleElement(KdbxXml.NODE_BINARIES)
            ?.let((el) sync* {
              for (final binaryNode in el.findElements(KdbxXml.NODE_BINARY)) {
                final id = int.parse(binaryNode.getAttribute(KdbxXml.ATTR_ID)!);
                yield MapEntry(
                  id,
                  KdbxBinary.readBinaryXml(binaryNode, isInline: false),
                );
              }
            })
            .toList()
            .let((binaries) {
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
                    final lastModified = iconNode
                        .singleElement(KdbxXml.NODE_LAST_MODIFICATION_TIME)
                        ?.innerText;
                    yield KdbxCustomIcon(
                        uuid: KdbxUuid(
                            iconNode.singleTextNode(KdbxXml.NODE_UUID)),
                        data: base64
                            .decode(iconNode.singleTextNode(KdbxXml.NODE_DATA)),
                        name: iconNode
                            .singleElement(KdbxXml.NODE_NAME)
                            ?.innerText,
                        lastModified: lastModified != null
                            ? DateTimeUtils.fromBase64(lastModified)
                            : null);
                  }
                })
                .map((e) => MapEntry(e.uuid, e))
                .let((that) => Map.fromEntries(that)) ??
            {},
        super.read();

  @override
  final KdbxReadWriteContext ctx;

  final KdbxMetaCustomData customData;

  /// only used in Kdbx 3
  final List<KdbxBinary>? binaries;

  final Map<KdbxUuid, KdbxCustomIcon> _customIcons;

  UnmodifiableMapView<KdbxUuid, KdbxCustomIcon> get customIcons =>
      UnmodifiableMapView(_customIcons);

  void addCustomIcon(KdbxCustomIcon customIcon) {
    if (_customIcons.containsKey(customIcon.uuid)) {
      return;
    }
    modify(() => _customIcons[customIcon.uuid] = customIcon);
  }

  void modifyCustomIcon(KdbxCustomIcon customIcon) {
    modify(() => _customIcons[customIcon.uuid] = customIcon);
  }

  void removeCustomIcon(KdbxUuid id) {
    if (!_customIcons.containsKey(id)) {
      return;
    }
    modify(() => _customIcons.remove(id));
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

  BrowserDbSettings? _browserSettings;
  BrowserDbSettings get browserSettings {
    if (_browserSettings == null) {
      final tempJson = customData['KeePassRPC.Config']?.value;

      if (tempJson != null) {
        _browserSettings = BrowserDbSettings.fromJson(tempJson);
      } else {
        _browserSettings = BrowserDbSettings();
      }
    }
    return _browserSettings!;
  }

  set browserSettings(BrowserDbSettings settings) {
    customData['KeePassRPC.Config'] =
        (value: settings.toJson(), lastModified: clock.now().toUtc());
    settingsChanged.setToNow();
  }

  KeeVaultEmbeddedConfig? _keeVaultSettings;
  KeeVaultEmbeddedConfig get keeVaultSettings {
    if (_keeVaultSettings == null) {
      final tempJson = customData['KeeVault.Config']?.value;

      if (tempJson != null) {
        _keeVaultSettings = KeeVaultEmbeddedConfig.fromJson(tempJson);
      } else {
        _keeVaultSettings = KeeVaultEmbeddedConfig();
      }
    }
    return _keeVaultSettings!;
  }

  set keeVaultSettings(KeeVaultEmbeddedConfig settings) {
    customData['KeeVault.Config'] =
        (value: settings.toJson(), lastModified: clock.now().toUtc());
    settingsChanged.setToNow();
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
                KdbxXml.NODE_DATA, base64.encode(customIcon.data)),
            if (ctx.version > KdbxVersion.V4 && customIcon.name != null)
              XmlUtils.createTextNode(KdbxXml.NODE_NAME, customIcon.name!),
            if (ctx.version > KdbxVersion.V4 && customIcon.lastModified != null)
              XmlUtils.createTextNode(KdbxXml.NODE_LAST_MODIFICATION_TIME,
                  DateTimeUtils.toBase64(customIcon.lastModified!)),
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
      // We assume that any client that has set a newer recycle bin UUID has also
      // configured the group correctly (e.g. setting the Trash icon)
    }
    final otherIsNewer = other.settingsChanged.isAfter(settingsChanged);

    // merge custom data
    mergeKdbxMetaCustomDataWithDates(
        customData, other.customData, ctx, otherIsNewer);

    // merge custom icons
    // Unused icons will be cleaned up later
    mergeCustomIconsWithDates(_customIcons, other._customIcons, ctx);

    if (other.entryTemplatesGroupChanged.isAfter(entryTemplatesGroupChanged)) {
      entryTemplatesGroup.set(other.entryTemplatesGroup.get());
      entryTemplatesGroupChanged.set(other.entryTemplatesGroupChanged.get());
    }

    if (otherIsNewer) {
      historyMaxItems.set(other.historyMaxItems.get());
      historyMaxSize.set(other.historyMaxSize.get());
      maintenanceHistoryDays.set(other.maintenanceHistoryDays.get());
      //TODO: keyChangeRec and keyChangeForce and database color
    }

    // Remove the cached versions of these so they have to be regenerated from the latest JSON when next requested
    _browserSettings = null;
    _keeVaultSettings = null;

    if (otherIsNewer) {
      settingsChanged.set(other.settingsChanged.get());
    }
  }

  void mergeKdbxMetaCustomDataWithDates(
      KdbxMetaCustomData local,
      KdbxMetaCustomData other,
      MergeContext ctx,
      bool assumeRemoteIsNewerWhenDatesMissing) {
    for (final entry in other.entries) {
      final otherKey = entry.key;
      final otherItem = entry.value;
      final existingItem = local[otherKey];
      if (existingItem != null) {
        if ((existingItem.lastModified == null ||
                otherItem.lastModified == null) &&
            assumeRemoteIsNewerWhenDatesMissing) {
          local[otherKey] = (
            value: otherItem.value,
            lastModified: otherItem.lastModified ?? clock.now().toUtc(),
          );
        } else if (existingItem.lastModified != null &&
            otherItem.lastModified != null &&
            otherItem.lastModified!.isAfter(existingItem.lastModified!)) {
          local[otherKey] = otherItem;
        }
      } else if (!ctx.deletedObjects.containsKey(otherKey)) {
        local[otherKey] = otherItem;
      }
    }
  }

  void mergeCustomIconsWithDates(
    Map<KdbxUuid, KdbxCustomIcon> local,
    Map<KdbxUuid, KdbxCustomIcon> other,
    MergeContext ctx,
  ) {
    for (final entry in other.entries) {
      final otherKey = entry.key;
      final otherItem = entry.value;
      final existingItem = local[otherKey];
      if (existingItem != null) {
        if (existingItem.lastModified == null) {
          local[otherKey] = KdbxCustomIcon(
            uuid: otherItem.uuid,
            data: otherItem.data,
            lastModified: otherItem.lastModified ?? clock.now().toUtc(),
            name: otherItem.name,
          );
        } else if (otherItem.lastModified != null &&
            otherItem.lastModified!.isAfter(existingItem.lastModified!)) {
          local[otherKey] = otherItem;
        }
      } else if (!ctx.deletedObjects.containsKey(otherKey)) {
        local[otherKey] = KdbxCustomIcon(
          uuid: otherItem.uuid,
          data: otherItem.data,
          lastModified: otherItem.lastModified ?? clock.now().toUtc(),
          name: otherItem.name,
        );
      }
    }
  }

  // Import changes in [other] into this meta data.
  void import(KdbxMeta other) {
    // import custom icons
    // Unused icons will be cleaned up later
    for (final otherCustomIcon in other._customIcons.values) {
      _customIcons[otherCustomIcon.uuid] ??= otherCustomIcon;
    }
  }
}

class KeeVaultEmbeddedConfig {
  KeeVaultEmbeddedConfig({
    this.version = 1,
    String? randomId,
    this.addon,
    this.vault,
  }) : randomId = randomId ?? const Uuid().v4();

  factory KeeVaultEmbeddedConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return KeeVaultEmbeddedConfig();
    }

    return KeeVaultEmbeddedConfig(
      version: map['version'] as int? ?? 1,
      randomId: map['randomId'] as String?,
      addon: map['addon'] != null
          ? Map<String, dynamic>.from(map['addon'] as Map<String, dynamic>)
          : <String, dynamic>{
              'prefs': <String, dynamic>{},
              'version': -1,
            },
      vault: map['vault'] != null
          ? Map<String, dynamic>.from(map['vault'] as Map<String, dynamic>)
          : <String, dynamic>{
              'prefs': <String, dynamic>{},
            },
    );
  }

  factory KeeVaultEmbeddedConfig.fromJson(String source) =>
      KeeVaultEmbeddedConfig.fromMap(
          json.decode(source) as Map<String, dynamic>?);

  int version;
  String randomId;
  Map<String, dynamic>? addon; // { "prefs": {}, "version": -1 };
  Map<String, dynamic>? vault; // { prefs: {} },

  KeeVaultEmbeddedConfig copyWith({
    int? version,
    String? randomId,
    Map<String, dynamic>? addon,
    Map<String, dynamic>? vault,
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
  // ignore: avoid_renaming_method_parameters
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
        const MapEquality().hash(addon) ^
        const MapEquality().hash(vault);
  }
}

class BrowserDbSettings {
  BrowserDbSettings({
    this.version = 3,
    this.rootUUID,
    this.defaultMatchAccuracy = MatchAccuracy.Domain,
    this.defaultPlaceholderHandling = 'Disabled',
    this.displayPriorityField = false,
    this.displayGlobalPlaceholderOption = false,
    Map<String, String>? matchedURLAccuracyOverrides,
  }) : matchedURLAccuracyOverrides =
            matchedURLAccuracyOverrides ?? <String, String>{};

  factory BrowserDbSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return BrowserDbSettings();
    }

    return BrowserDbSettings(
        version: map['version'] as int? ?? 3,
        rootUUID: map['rootUUID'] as String?,
        defaultMatchAccuracy: MatchAccuracy.values.singleWhereOrNull(
                (val) => val == map['defaultMatchAccuracy']) ??
            MatchAccuracy.Domain,
        defaultPlaceholderHandling:
            map['defaultPlaceholderHandling'] as String? ?? 'Default',
        displayPriorityField: map['displayPriorityField'] as bool? ?? false,
        displayGlobalPlaceholderOption:
            map['displayGlobalPlaceholderOption'] as bool? ?? false,
        matchedURLAccuracyOverrides:
            (map['matchedURLAccuracyOverrides'] as Map<String, dynamic>?)
                    ?.cast<String, String>() ??
                <String, String>{});
  }

  factory BrowserDbSettings.fromJson(String source) =>
      BrowserDbSettings.fromMap(json.decode(source) as Map<String, dynamic>?);

  int version;
  String? rootUUID;
  // enum
  MatchAccuracy defaultMatchAccuracy;
  String defaultPlaceholderHandling;
  bool displayPriorityField;
  bool displayGlobalPlaceholderOption;
  Map<String, String> matchedURLAccuracyOverrides;

  BrowserDbSettings copyWith({
    int? version,
    String? rootUUID,
    MatchAccuracy? defaultMatchAccuracy,
    String? defaultPlaceholderHandling,
    bool? displayPriorityField,
    bool? displayGlobalPlaceholderOption,
    Map<String, String>? matchedURLAccuracyOverrides,
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
        const MapEquality().hash(matchedURLAccuracyOverrides);
  }
}

class KdbxCustomIcon {
  KdbxCustomIcon({
    required this.uuid,
    required this.data,
    this.name,
    this.lastModified,
  });

  /// uuid of the icon, must be unique within each file.
  final KdbxUuid uuid;

  /// Encoded png data of the image. will be base64 encoded into the kdbx file.
  final Uint8List data;

  final String? name;

  final DateTime? lastModified;
}
