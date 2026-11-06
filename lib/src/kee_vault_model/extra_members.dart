import 'package:collection/collection.dart';

/// Preservation of JSON members that the model does not understand.
///
/// Kee Vault 2 and KeePassRPC may add members, or new enum names, that this
/// model does not know yet. Each model keeps them in `extraMembers`, carries
/// them through `copyWith`, writes them back in `toMap`, and compares them in
/// `==` and `hashCode`.
///
/// An enum member whose value is not one of the enum's names has a null typed
/// field. Its raw value is kept in `extraMembers` under the member's own name,
/// and `toMap` writes it back because the typed field is null. If the typed
/// field is later set, the known value wins.
///
/// Known members are written first, in the model's own order. An extra member
/// is written only when no known member with that name has a value.

/// The members of [map] that are not in [knownKeys], plus the members of
/// [unparsedEnums] whose typed value is null (a value the enum does not know).
Map<String, dynamic> extraMembersOf(
  Map<String, dynamic> map,
  Set<String> knownKeys, {
  Map<String, Object?> unparsedEnums = const {},
}) {
  return {
    for (final entry in map.entries)
      if (!knownKeys.contains(entry.key) ||
          (unparsedEnums.containsKey(entry.key) &&
              unparsedEnums[entry.key] == null))
        entry.key: entry.value,
  };
}

/// [known] followed by the members of [extra] that [known] does not give a value.
Map<String, dynamic> withExtraMembers(
  Map<String, dynamic> known,
  Map<String, dynamic> extra,
) {
  return {
    ...known,
    for (final entry in extra.entries)
      if (known[entry.key] == null) entry.key: entry.value,
  };
}

/// Equality of two extra-member maps (deep, so nested lists and maps compare by value).
bool extraMembersEqual(Map<String, dynamic> a, Map<String, dynamic> b) =>
    const DeepCollectionEquality().equals(a, b);

int extraMembersHash(Map<String, dynamic> extra) =>
    const DeepCollectionEquality().hash(extra);
