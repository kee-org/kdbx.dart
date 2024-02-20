import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:kdbx/src/kee_vault_model/enums.dart';
import 'package:kdbx/src/kee_vault_model/field_matcher.dart';
import 'package:kdbx/src/utils/field_type_utils.dart';

class FieldMatcherConfig {
  FieldMatcherConfig({
    this.matcherType,
    this.customMatcher,
    this.weight, // 0 = client decides or ignores locator
    this.actionOnMatch,
  });

  FieldMatcherConfig.forSingleClientMatch(String? id, String? name, String fft)
      : this(
          customMatcher: FieldMatcher(
            ids: id == null ? [] : [id],
            names: name == null ? [] : [name],
            types: [Utilities.formFieldTypeToHtmlType(fft)],
            queries: [],
          ),
        );

  FieldMatcherConfig.forSingleClientMatchHtmlType(
      String? id, String? name, String? htmlType, String? domSelector)
      : this(
          customMatcher: FieldMatcher(
            ids: id == null ? [] : [id],
            names: name == null ? [] : [name],
            types: htmlType == null ? [] : [htmlType],
            queries: domSelector == null ? [] : [domSelector],
          ),
        );

  FieldMatcherConfig copyWith({
    FieldMatcherType? matcherType,
    FieldMatcher? customMatcher,
    num? weight,
    MatchAction? actionOnMatch,
  }) {
    return FieldMatcherConfig(
      matcherType: matcherType ?? this.matcherType,
      customMatcher: customMatcher ?? this.customMatcher,
      weight: weight ?? this.weight,
      actionOnMatch: actionOnMatch ?? this.actionOnMatch,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (matcherType != null && matcherType != FieldMatcherType.Custom)
        'matcherType': matcherType?.name,
      if (customMatcher != null) 'customMatcher': customMatcher?.toMap(),
      if (weight != null) 'weight': weight,
      if (actionOnMatch != null) 'actionOnMatch': actionOnMatch?.name,
    };
  }

  factory FieldMatcherConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return FieldMatcherConfig();
    }

    return FieldMatcherConfig(
      matcherType: FieldMatcherType.values
          .firstWhereOrNull((v) => v.name == map['matchLogic']),
      customMatcher: map['customMatcher'] != null
          ? FieldMatcher.fromMap(map['customMatcher'] as Map<String, dynamic>)
          : null,
      weight: map['weight'] as int?,
      actionOnMatch: MatchAction.values
          .firstWhereOrNull((v) => v.name == map['actionOnMatch']),
    );
  }

  String toJson() => json.encode(toMap());

  factory FieldMatcherConfig.fromJson(String source) =>
      FieldMatcherConfig.fromMap(json.decode(source) as Map<String, dynamic>?);

  @override
  String toString() {
    return 'FieldMatcherConfig(matcherType: $matcherType, customMatcher: $customMatcher, weight: $weight, actionOnMatch: $actionOnMatch)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is FieldMatcherConfig &&
        other.matcherType == matcherType &&
        other.customMatcher == customMatcher &&
        other.weight == weight &&
        other.actionOnMatch == actionOnMatch;
  }

  @override
  int get hashCode {
    return matcherType.hashCode ^
        customMatcher.hashCode ^
        weight.hashCode ^
        actionOnMatch.hashCode;
  }

  FieldMatcherType? matcherType;
  FieldMatcher? customMatcher;
  num? weight; // 0 = client decides or ignores locator
  MatchAction? actionOnMatch;
}
