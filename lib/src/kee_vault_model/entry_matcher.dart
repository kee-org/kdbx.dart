import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:kdbx/src/kee_vault_model/enums.dart';

class EntryMatcher {
  EntryMatcher({
    this.matchLogic,
    this.queries = const [],
    this.pageTitles = const [],
  });

  EntryMatcher copyWith({
    MatcherLogic? matchLogic,
    List<String>? queries,
    List<String>? pageTitles,
  }) {
    return EntryMatcher(
      matchLogic: matchLogic ?? this.matchLogic,
      queries: queries ?? this.queries,
      pageTitles: pageTitles ?? this.pageTitles,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'matchLogic': matchLogic?.name,
      'queries': queries,
      'pageTitles': pageTitles,
    };
  }

  factory EntryMatcher.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return EntryMatcher();
    }

    return EntryMatcher(
      matchLogic: MatcherLogic.values
          .firstWhereOrNull((v) => v.name == map['matchLogic']),
      queries: (map['queries'] as List<dynamic>?)?.cast<String>() ?? [],
      pageTitles: (map['pageTitles'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  String toJson() => json.encode(toMap());

  factory EntryMatcher.fromJson(String source) =>
      EntryMatcher.fromMap(json.decode(source) as Map<String, dynamic>?);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    final listEquals = const DeepCollectionEquality().equals;

    return other is EntryMatcher &&
        other.matchLogic == matchLogic &&
        listEquals(other.queries, queries) &&
        listEquals(other.pageTitles, pageTitles);
  }

  @override
  int get hashCode {
    return matchLogic.hashCode ^ queries.hashCode ^ pageTitles.hashCode;
  }

  MatcherLogic? matchLogic; // default to Client initially
  List<String> queries; // HTML DOM select query
  List<String> pageTitles; // HTML Page title contains
}
