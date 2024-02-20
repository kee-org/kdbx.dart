import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:kdbx/src/kee_vault_model/browser_entry_settings_v1.dart';
import 'package:kdbx/src/kee_vault_model/entry_matcher_config.dart';
import 'package:kdbx/src/kee_vault_model/enums.dart';
import 'package:kdbx/src/kee_vault_model/field.dart';

class BrowserEntrySettings {
  BrowserEntrySettings({
    this.version = 2,
    List<Pattern>? includeUrls,
    List<Pattern>? excludeUrls,
    this.realm = '',
    List<String>? authenticationMethods,
    this.behaviour = BrowserAutoFillBehaviour.Default,
    required this.matcherConfigs,
    List<Field>? fields,
  })  : authenticationMethods = authenticationMethods ?? [],
        includeUrls = includeUrls ?? [],
        excludeUrls = excludeUrls ?? [],
        fields = fields ?? [];

  factory BrowserEntrySettings.fromMap(Map<String, dynamic>? map,
      {required MatchAccuracy minimumMatchAccuracy}) {
    if (map == null) {
      return BrowserEntrySettings(matcherConfigs: [
        EntryMatcherConfig.forDefaultUrlMatchBehaviour(minimumMatchAccuracy)
      ]);
    }

    return BrowserEntrySettings(
      version: map['version'] as int? ?? 2,
      includeUrls: getIncludeUrls(map),
      excludeUrls: getExcludeUrls(map),
      realm: map['hTTPRealm'] as String?,
      authenticationMethods:
          (map['authenticationMethods'] as List<dynamic>?)?.cast<String>() ??
              [],
      behaviour: BrowserAutoFillBehaviour.values
          .firstWhereOrNull((v) => v.name == map['behaviour']),
      matcherConfigs: List<EntryMatcherConfig>.from((map['matcherConfigs']
                  as List<dynamic>?)
              ?.cast<Map<String, dynamic>>()
              .map<EntryMatcherConfig>((x) => EntryMatcherConfig.fromMap(x)) ??
          <EntryMatcherConfig>[]),
      fields: List<Field>.from((map['fields'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>()
              .map<Field>((x) => Field.fromMap(x)) ??
          <Field>[]),
    );
  }

  factory BrowserEntrySettings.fromJson(String source,
          {required MatchAccuracy minimumMatchAccuracy}) =>
      BrowserEntrySettings.fromMap(json.decode(source) as Map<String, dynamic>?,
          minimumMatchAccuracy: minimumMatchAccuracy);

  int version;
  List<Pattern> includeUrls;
  List<Pattern> excludeUrls;
  String? realm;
  List<String>? authenticationMethods;
  // enum
  BrowserAutoFillBehaviour? behaviour;
  List<EntryMatcherConfig> matcherConfigs;
  List<Field>? fields;

  BrowserEntrySettings copyWith({
    int? version,
    List<Pattern>? includeUrls,
    List<Pattern>? excludeUrls,
    String? realm,
    List<String>? authenticationMethods,
    BrowserAutoFillBehaviour? behaviour,
    List<EntryMatcherConfig>? matcherConfigs,
    List<Field>? fields,
  }) {
    return BrowserEntrySettings(
      version: version ?? this.version,
      behaviour: behaviour ?? this.behaviour,
      authenticationMethods:
          authenticationMethods ?? this.authenticationMethods,
      realm: realm ?? this.realm,
      includeUrls: includeUrls ?? this.includeUrls,
      excludeUrls: excludeUrls ?? this.excludeUrls,
      fields: fields ?? this.fields,
      matcherConfigs: matcherConfigs ?? this.matcherConfigs,
    );
  }

  BrowserEntrySettingsV1 convertToV1() {
    return BrowserEntrySettingsV1(
        minimumMatchAccuracy: matcherConfigs
                .firstWhereOrNull(
                    (element) => element.matcherType == EntryMatcherType.Url)
                ?.urlMatchMethod ??
            MatchAccuracy.Domain,
        realm: realm ?? '',
        fields: fields?.map((f) => f.convertToV1()).nonNulls.toList(),
        behaviour: behaviour ?? BrowserAutoFillBehaviour.Default,
        excludeUrls: excludeUrls,
        includeUrls: includeUrls,
        priority: 0,
        hide: matcherConfigs
            .any((element) => element.matcherType == EntryMatcherType.Hide));
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
      if (altURLs.isNotEmpty) 'altURLs': altURLs,
      if (regExURLs.isNotEmpty) 'regExURLs': regExURLs,
      if (blockedURLs.isNotEmpty) 'blockedURLs': blockedURLs,
      if (regExBlockedURLs.isNotEmpty) 'regExBlockedURLs': regExBlockedURLs,
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
      'authenticationMethods': authenticationMethods,
      if (realm?.isNotEmpty ?? false) 'hTTPRealm': realm,
      'matcherConfigs': matcherConfigs.map((x) => x.toMap()).toList(),
      if (fields != null) 'fields': fields?.map((x) => x.toMap()).toList(),
      if (behaviour != null && behaviour != BrowserAutoFillBehaviour.Default)
        'behaviour': behaviour?.name,
      ...parseUrls(includeUrls, excludeUrls),
    };
  }

  String toJson() => json.encode(toMap());

  @override
  String toString() {
    return 'BrowserSettingsModel(version: $version, behaviour: $behaviour, realm: $realm, includeUrls: $includeUrls, excludeUrls: $excludeUrls, fields: $fields)';
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
        o.authenticationMethods == authenticationMethods &&
        o.realm == realm &&
        unOrdDeepEq(o.matcherConfigs, matcherConfigs) &&
        unOrdDeepEq(o.includeUrls, includeUrls) &&
        unOrdDeepEq(o.excludeUrls, excludeUrls) &&
        unOrdDeepEq(o.fields, fields);
  }

  @override
  int get hashCode {
    return version.hashCode ^
        behaviour.hashCode ^
        authenticationMethods.hashCode ^
        realm.hashCode ^
        matcherConfigs.hashCode ^
        includeUrls.hashCode ^
        excludeUrls.hashCode ^
        fields.hashCode;
  }
}
