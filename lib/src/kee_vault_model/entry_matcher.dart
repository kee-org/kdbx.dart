import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:kdbx/src/kee_vault_model/enums.dart';
import 'package:kdbx/src/kee_vault_model/extra_members.dart';

const _knownMembers = {
  'matchLogic',
  'queries',
  'pageTitles',
};

class EntryMatcher {
  EntryMatcher({
    this.matchLogic,
    this.queries = const [],
    this.pageTitles = const [],
    Map<String, dynamic>? extraMembers,
  }) : extraMembers = Map.unmodifiable(extraMembers ?? const {});

  factory EntryMatcher.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return EntryMatcher();
    }

    final matchLogic = MatcherLogic.values
        .firstWhereOrNull((v) => v.name == map['matchLogic']);
    return EntryMatcher(
      matchLogic: matchLogic,
      queries: (map['queries'] as List<dynamic>?)?.cast<String>() ?? [],
      pageTitles: (map['pageTitles'] as List<dynamic>?)?.cast<String>() ?? [],
      extraMembers: extraMembersOf(map, _knownMembers,
          unparsedEnums: {'matchLogic': matchLogic}),
    );
  }

  factory EntryMatcher.fromJson(String source) =>
      EntryMatcher.fromMap(json.decode(source) as Map<String, dynamic>?);

  EntryMatcher copyWith({
    MatcherLogic? matchLogic,
    List<String>? queries,
    List<String>? pageTitles,
    Map<String, dynamic>? extraMembers,
  }) {
    return EntryMatcher(
      matchLogic: matchLogic ?? this.matchLogic,
      queries: queries ?? this.queries,
      pageTitles: pageTitles ?? this.pageTitles,
      extraMembers: extraMembers ?? this.extraMembers,
    );
  }

  Map<String, dynamic> toMap() {
    return withExtraMembers({
      'matchLogic': matchLogic?.name,
      'queries': queries,
      'pageTitles': pageTitles,
    }, extraMembers);
  }

  String toJson() => json.encode(toMap());

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    final unOrdDeepEq = const DeepCollectionEquality.unordered().equals;

    return other is EntryMatcher &&
        other.matchLogic == matchLogic &&
        unOrdDeepEq(other.queries, queries) &&
        unOrdDeepEq(other.pageTitles, pageTitles) &&
        extraMembersEqual(other.extraMembers, extraMembers);
  }

  @override
  int get hashCode {
    return matchLogic.hashCode ^
        const ListEquality().hash(queries) ^
        const ListEquality().hash(pageTitles) ^
        extraMembersHash(extraMembers);
  }

  MatcherLogic? matchLogic; // default to Client initially
  List<String> queries; // HTML DOM select query
  List<String> pageTitles; // HTML Page title contains

  /// JSON members this version of the model does not know, written back on save.
  /// See `extra_members.dart`.
  final Map<String, dynamic> extraMembers;
}
