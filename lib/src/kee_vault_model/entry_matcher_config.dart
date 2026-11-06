import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:kdbx/src/kee_vault_model/entry_matcher.dart';
import 'package:kdbx/src/kee_vault_model/enums.dart';
import 'package:kdbx/src/kee_vault_model/extra_members.dart';

const _knownMembers = {
  'matcherType',
  'customMatcher',
  'urlMatchMethod',
  'weight',
  'actionOnMatch',
  'actionOnNoMatch',
};

class EntryMatcherConfig {
  EntryMatcherConfig({
    this.matcherType,
    this.customMatcher,
    this.urlMatchMethod,
    this.weight, // 0 = client decides or ignores locator
    this.actionOnMatch,
    this.actionOnNoMatch,
    Map<String, dynamic>? extraMembers,
  }) : extraMembers = Map.unmodifiable(extraMembers ?? const {});

  factory EntryMatcherConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return EntryMatcherConfig();
    }

    final matcherType = EntryMatcherType.values
        .firstWhereOrNull((v) => v.name == map['matcherType']);
    final urlMatchMethod = MatchAccuracy.values
        .firstWhereOrNull((v) => v.name == map['urlMatchMethod']);
    final actionOnMatch = MatchAction.values
        .firstWhereOrNull((v) => v.name == map['actionOnMatch']);
    final actionOnNoMatch = MatchAction.values
        .firstWhereOrNull((v) => v.name == map['actionOnNoMatch']);
    return EntryMatcherConfig(
      matcherType: matcherType,
      customMatcher: map['customMatcher'] != null
          ? EntryMatcher.fromMap(map['customMatcher'] as Map<String, dynamic>)
          : null,
      urlMatchMethod: urlMatchMethod,
      weight: map['weight'] as int?,
      actionOnMatch: actionOnMatch,
      actionOnNoMatch: actionOnNoMatch,
      extraMembers: extraMembersOf(map, _knownMembers, unparsedEnums: {
        'matcherType': matcherType,
        'urlMatchMethod': urlMatchMethod,
        'actionOnMatch': actionOnMatch,
        'actionOnNoMatch': actionOnNoMatch,
      }),
    );
  }

  factory EntryMatcherConfig.fromJson(String source) =>
      EntryMatcherConfig.fromMap(json.decode(source) as Map<String, dynamic>);

  EntryMatcherConfig.forDefaultUrlMatchBehaviour(MatchAccuracy ma)
      : this(
          matcherType: EntryMatcherType.Url,
          urlMatchMethod: ma,
        );

  EntryMatcherConfig copyWith({
    EntryMatcherType? matcherType,
    EntryMatcher? customMatcher,
    MatchAccuracy? urlMatchMethod,
    num? weight,
    MatchAction? actionOnMatch,
    MatchAction? actionOnNoMatch,
    Map<String, dynamic>? extraMembers,
  }) {
    return EntryMatcherConfig(
      matcherType: matcherType ?? this.matcherType,
      customMatcher: customMatcher ?? this.customMatcher,
      urlMatchMethod: urlMatchMethod ?? this.urlMatchMethod,
      weight: weight ?? this.weight,
      actionOnMatch: actionOnMatch ?? this.actionOnMatch,
      actionOnNoMatch: actionOnNoMatch ?? this.actionOnNoMatch,
      extraMembers: extraMembers ?? this.extraMembers,
    );
  }

  Map<String, dynamic> toMap() {
    return withExtraMembers({
      'matcherType': matcherType?.name,
      if (customMatcher != null) 'customMatcher': customMatcher?.toMap(),
      if (urlMatchMethod != null && urlMatchMethod != MatchAccuracy.Domain)
        'urlMatchMethod': urlMatchMethod?.name,
      if (weight != null) 'weight': weight,
      if (actionOnMatch != null) 'actionOnMatch': actionOnMatch?.name,
      if (actionOnNoMatch != null) 'actionOnNoMatch': actionOnNoMatch?.name,
    }, extraMembers);
  }

  String toJson() => json.encode(toMap());

  @override
  String toString() {
    return 'EntryMatcherConfig(matcherType: $matcherType, customMatcher: $customMatcher, urlMatchMethod: $urlMatchMethod, weight: $weight, actionOnMatch: $actionOnMatch, actionOnNoMatch: $actionOnNoMatch)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is EntryMatcherConfig &&
        other.matcherType == matcherType &&
        other.customMatcher == customMatcher &&
        other.urlMatchMethod == urlMatchMethod &&
        other.weight == weight &&
        other.actionOnMatch == actionOnMatch &&
        other.actionOnNoMatch == actionOnNoMatch &&
        extraMembersEqual(other.extraMembers, extraMembers);
  }

  @override
  int get hashCode {
    return matcherType.hashCode ^
        customMatcher.hashCode ^
        urlMatchMethod.hashCode ^
        weight.hashCode ^
        actionOnMatch.hashCode ^
        actionOnNoMatch.hashCode ^
        extraMembersHash(extraMembers);
  }

  EntryMatcherType? matcherType;
  EntryMatcher? customMatcher;
  MatchAccuracy? urlMatchMethod;
  num? weight; // 0 = client decides or ignores locator
  MatchAction? actionOnMatch;
  MatchAction?
      actionOnNoMatch; // critical to use TotalBlock here for Url match type

  /// JSON members this version of the model does not know, written back on save.
  /// See `extra_members.dart`.
  final Map<String, dynamic> extraMembers;
}
