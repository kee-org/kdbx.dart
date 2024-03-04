import 'dart:convert';
import 'dart:math';
import 'package:collection/collection.dart';
import 'package:kdbx/src/kee_vault_model/browser_entry_settings.dart';
import 'package:kdbx/src/kee_vault_model/browser_field_model_v1.dart';
import 'package:kdbx/src/kee_vault_model/entry_matcher_config.dart';
import 'package:kdbx/src/kee_vault_model/enums.dart';
import 'package:kdbx/src/kee_vault_model/field.dart';

import '../utils/field_type_utils.dart';
import '../utils/guid_service.dart';
import 'field_matcher_config.dart';
import 'form_field_type.dart';

class BrowserEntrySettingsV1 {
  BrowserEntrySettingsV1({
    this.version = 1,
    this.behaviour = BrowserAutoFillBehaviour.Default,
    required this.minimumMatchAccuracy,
    this.priority = 0,
    this.hide = false,
    this.realm = '',
    List<Pattern>? includeUrls,
    List<Pattern>? excludeUrls,
    List<BrowserFieldModelV1>? fields,
  })  : includeUrls = includeUrls ?? [],
        excludeUrls = excludeUrls ?? [],
        fields = fields ?? [];

  factory BrowserEntrySettingsV1.fromMap(Map<String, dynamic>? map,
      {required MatchAccuracy minimumMatchAccuracy}) {
    if (map == null) {
      return BrowserEntrySettingsV1(minimumMatchAccuracy: minimumMatchAccuracy);
    }

    return BrowserEntrySettingsV1(
      version: map['version'] as int? ?? 1,
      behaviour: getBehaviour(map),
      minimumMatchAccuracy: getMam(map),
      priority: map['priority'] as int? ?? 0,
      hide: map['hide'] as bool? ?? false,
      realm: map['hTTPRealm'] as String?,
      includeUrls: getIncludeUrls(map),
      excludeUrls: getExcludeUrls(map),
      fields: List<BrowserFieldModelV1>.from(
          (map['formFieldList'] as List<dynamic>?)
                  ?.cast<Map<String, dynamic>>()
                  .map<BrowserFieldModelV1>(
                      (x) => BrowserFieldModelV1.fromMap(x)) ??
              <BrowserFieldModelV1>[]),
    );
  }

  factory BrowserEntrySettingsV1.fromJson(String source,
      {required MatchAccuracy minimumMatchAccuracy}) {
    if (source.isEmpty) {
      return BrowserEntrySettingsV1(minimumMatchAccuracy: minimumMatchAccuracy);
    }
    return BrowserEntrySettingsV1.fromMap(
        json.decode(source) as Map<String, dynamic>?,
        minimumMatchAccuracy: minimumMatchAccuracy);
  }

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
  List<BrowserFieldModelV1> fields;

  BrowserEntrySettingsV1 copyWith({
    int? version,
    BrowserAutoFillBehaviour? behaviour,
    MatchAccuracy? minimumMatchAccuracy,
    int? priority,
    bool? hide,
    String? realm,
    List<Pattern>? includeUrls,
    List<Pattern>? excludeUrls,
    List<BrowserFieldModelV1>? fields,
  }) {
    return BrowserEntrySettingsV1(
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
    for (final p in includeUrls) {
      if (p is RegExp) {
        regExURLs.add(p.pattern);
      } else if (p is String) {
        altURLs.add(p);
      }
    }
    for (final p in excludeUrls) {
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
    if (altUrls != null) {
      altUrls.forEach(includeUrls.add);
    }
    if (regExURLs != null) {
      for (final url in regExURLs) {
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
    if (blockedURLs != null) {
      blockedURLs.forEach(excludeUrls.add);
    }
    if (regExBlockedURLs != null) {
      for (final url in regExBlockedURLs) {
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
    return 'BrowserSettingsModelV1(version: $version, behaviour: $behaviour, minimumMatchAccuracy: $minimumMatchAccuracy, priority: $priority, hide: $hide, realm: $realm, includeUrls: $includeUrls, excludeUrls: $excludeUrls, fields: $fields)';
  }

  @override
  // ignore: avoid_renaming_method_parameters
  bool operator ==(Object o) {
    if (identical(this, o)) {
      return true;
    }
    final unOrdDeepEq = const DeepCollectionEquality.unordered().equals;
    return o is BrowserEntrySettingsV1 &&
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
        const ListEquality().hash(includeUrls) ^
        const ListEquality().hash(excludeUrls) ^
        const ListEquality().hash(fields);
  }

  BrowserEntrySettings convertToV2(IGuidService guidService) {
    final List<EntryMatcherConfig> mcList = [
      EntryMatcherConfig.forDefaultUrlMatchBehaviour(minimumMatchAccuracy),
      if (hide) EntryMatcherConfig(matcherType: EntryMatcherType.Hide)
    ];

    final conf2 = BrowserEntrySettings(
      behaviour: behaviour,
      authenticationMethods: ['password'],
      matcherConfigs: mcList,
      includeUrls: includeUrls,
      excludeUrls: excludeUrls,
      realm: realm,
      fields: convertFields(fields, guidService),
    );

    return conf2;
  }

  List<Field> convertFields(
      List<BrowserFieldModelV1> formFieldList, IGuidService guidService) {
    final List<Field> fields = [];
    bool usernameFound = false;
    bool passwordFound = false;
    for (final ff in formFieldList) {
      if (ff.value == '{USERNAME}') {
        usernameFound = true;
        final mc = !((ff.fieldId?.isNotEmpty ?? false) ||
                (ff.name?.isNotEmpty ?? false))
            ? FieldMatcherConfig(
                matcherType: FieldMatcherType.UsernameDefaultHeuristic)
            : FieldMatcherConfig.forSingleClientMatch(
                FormFieldType.USERNAME,
                id: ff.fieldId,
                name: ff.name,
              );
        final f = Field(
          valuePath: 'UserName',
          page: max(ff.page, 1),
          uuid: guidService.newGuidAsBase64(),
          type: FieldType.Text,
          matcherConfigs: [mc],
        );
        if (ff.placeholderHandling != PlaceholderHandling.Default.name) {
          f.placeholderHandling = PlaceholderHandling.values
              .firstWhereOrNull((v) => v.name == ff.placeholderHandling);
        }
        fields.add(f);
      } else if (ff.value == '{PASSWORD}') {
        passwordFound = true;
        final mc = !((ff.fieldId?.isNotEmpty ?? false) ||
                (ff.name?.isNotEmpty ?? false))
            ? FieldMatcherConfig(
                matcherType: FieldMatcherType.PasswordDefaultHeuristic)
            : FieldMatcherConfig.forSingleClientMatch(
                FormFieldType.PASSWORD,
                id: ff.fieldId,
                name: ff.name,
              );
        final f = Field(
            valuePath: 'Password',
            page: max(ff.page, 1),
            uuid: guidService.newGuidAsBase64(),
            type: FieldType.Password,
            matcherConfigs: [mc]);
        if (ff.placeholderHandling != PlaceholderHandling.Default.name) {
          f.placeholderHandling = PlaceholderHandling.values
              .firstWhereOrNull((v) => v.name == ff.placeholderHandling);
        }
        fields.add(f);
      } else {
        final mc = FieldMatcherConfig.forSingleClientMatch(
          ff.type ?? FormFieldType.TEXT,
          id: ff.fieldId,
          name: ff.name,
        );
        final newUniqueId = guidService.newGuidAsBase64();
        final f = Field(
            name: (ff.displayName?.isNotEmpty ?? false)
                ? ff.displayName
                : newUniqueId,
            valuePath: '.',
            page: max(ff.page, 1),
            uuid: newUniqueId,
            type: Utilities.formFieldTypeToFieldType(
                ff.type ?? FormFieldType.TEXT),
            matcherConfigs: [mc],
            value: ff.value);
        if (ff.placeholderHandling != PlaceholderHandling.Default.name) {
          f.placeholderHandling = PlaceholderHandling.values
              .firstWhereOrNull((v) => v.name == ff.placeholderHandling);
        }
        fields.add(f);
      }
    }

    if (!usernameFound) {
      fields.add(Field(
          valuePath: 'UserName',
          uuid: guidService.newGuidAsBase64(),
          type: FieldType.Text,
          matcherConfigs: [
            FieldMatcherConfig(
                matcherType: FieldMatcherType.UsernameDefaultHeuristic)
          ]));
    }
    if (!passwordFound) {
      fields.add(Field(
          valuePath: 'Password',
          uuid: guidService.newGuidAsBase64(),
          type: FieldType.Password,
          matcherConfigs: [
            FieldMatcherConfig(
                matcherType: FieldMatcherType.PasswordDefaultHeuristic)
          ]));
    }

    return fields;
  }
}
