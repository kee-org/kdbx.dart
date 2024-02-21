import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:kdbx/src/kee_vault_model/enums.dart';

class FieldMatcher {
  FieldMatcher({
    this.matchLogic,
    this.ids = const [],
    this.names = const [],
    this.types = const [],
    this.queries = const [],
    this.labels = const [],
    this.autocompleteValues = const [],
    this.maxLength,
    this.minLength,
  });

  factory FieldMatcher.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return FieldMatcher();
    }

    return FieldMatcher(
      matchLogic: MatcherLogic.values
          .firstWhereOrNull((v) => v.name == map['matchLogic']),
      ids: (map['ids'] as List<dynamic>?)?.cast<String>() ?? [],
      names: (map['names'] as List<dynamic>?)?.cast<String>() ?? [],
      types: (map['types'] as List<dynamic>?)?.cast<String>() ?? [],
      queries: (map['queries'] as List<dynamic>?)?.cast<String>() ?? [],
      labels: (map['labels'] as List<dynamic>?)?.cast<String>() ?? [],
      autocompleteValues:
          (map['autocompleteValues'] as List<dynamic>?)?.cast<String>() ?? [],
      maxLength: map['maxLength'] as int?,
      minLength: map['minLength'] as int?,
    );
  }

  factory FieldMatcher.fromJson(String source) =>
      FieldMatcher.fromMap(json.decode(source) as Map<String, dynamic>?);

  FieldMatcher copyWith({
    MatcherLogic? matchLogic,
    List<String>? ids,
    List<String>? names,
    List<String>? types,
    List<String>? queries,
    List<String>? labels,
    List<String>? autocompleteValues,
    int? maxLength,
    int? minLength,
  }) {
    return FieldMatcher(
      matchLogic: matchLogic ?? this.matchLogic,
      ids: ids ?? this.ids,
      names: names ?? this.names,
      types: types ?? this.types,
      queries: queries ?? this.queries,
      labels: labels ?? this.labels,
      autocompleteValues: autocompleteValues ?? this.autocompleteValues,
      maxLength: maxLength ?? this.maxLength,
      minLength: minLength ?? this.minLength,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (matchLogic != null && matchLogic != MatcherLogic.Client)
        'matchLogic': matchLogic?.name,
      if (ids.isNotEmpty) 'ids': ids,
      if (names.isNotEmpty) 'names': names,
      if (types.isNotEmpty) 'types': types,
      if (queries.isNotEmpty) 'queries': queries,
      if (labels.isNotEmpty) 'labels': labels,
      if (autocompleteValues.isNotEmpty)
        'autocompleteValues': autocompleteValues,
      if (maxLength != null) 'maxLength': maxLength,
      if (minLength != null) 'minLength': minLength,
    };
  }

  String toJson() => json.encode(toMap());

  @override
  String toString() {
    return 'FieldMatcher(matchLogic: $matchLogic, ids: $ids, names: $names, types: $types, queries: $queries, labels: $labels, autocompleteValues: $autocompleteValues, maxLength: $maxLength, minLength: $minLength)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    final unOrdDeepEq = const DeepCollectionEquality.unordered().equals;

    return other is FieldMatcher &&
        other.matchLogic == matchLogic &&
        unOrdDeepEq(other.ids, ids) &&
        unOrdDeepEq(other.names, names) &&
        unOrdDeepEq(other.types, types) &&
        unOrdDeepEq(other.queries, queries) &&
        unOrdDeepEq(other.labels, labels) &&
        unOrdDeepEq(other.autocompleteValues, autocompleteValues) &&
        other.maxLength == maxLength &&
        other.minLength == minLength;
  }

  @override
  int get hashCode {
    return matchLogic.hashCode ^
        ids.hashCode ^
        names.hashCode ^
        types.hashCode ^
        queries.hashCode ^
        labels.hashCode ^
        autocompleteValues.hashCode ^
        maxLength.hashCode ^
        minLength.hashCode;
  }

  MatcherLogic? matchLogic; // default to Client initially
  List<String> ids; // HTML id attribute
  List<String> names; // HTML name attribute
  List<String> types; // HTML input type
  List<String> queries; // HTML DOM select query
  List<String> labels; // HTML Label or otherwise visible UI label
  List<String> autocompleteValues; // HTML autocomplete attribute values
  int? maxLength; // max chars allowed in a candidate field for this to match
  int? minLength; // min chars allowed in a candidate field for this to match
}
