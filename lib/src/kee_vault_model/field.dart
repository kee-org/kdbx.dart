import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:kdbx/src/kee_vault_model/browser_field_model_v1.dart';
import 'package:kdbx/src/kee_vault_model/enums.dart';
import 'package:kdbx/src/kee_vault_model/extra_members.dart';
import 'package:kdbx/src/kee_vault_model/field_matcher_config.dart';
import 'package:kdbx/src/kee_vault_model/form_field_type.dart';
import 'package:kdbx/src/utils/field_type_utils.dart';

const _knownMembers = {
  'uuid',
  'name',
  'valuePath',
  'value',
  'page',
  'type',
  'placeholderHandling',
  'matcherConfigs',
};

class Field {
  Field({
    this.uuid,
    this.name,
    this.valuePath,
    this.value,
    this.page = 1,
    this.type,
    this.placeholderHandling,
    this.matcherConfigs,
    Map<String, dynamic>? extraMembers,
  }) : extraMembers = Map.unmodifiable(extraMembers ?? const {});

  factory Field.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return Field();
    }
    final type =
        FieldType.values.firstWhereOrNull((v) => v.name == map['type']);
    final placeholderHandling = PlaceholderHandling.values
        .firstWhereOrNull((v) => v.name == map['placeholderHandling']);
    return Field(
      uuid: map['uuid'] as String?,
      name: map['name'] as String?,
      valuePath: map['valuePath'] as String?,
      value: map['value'] as String?,
      page: map['page'] as int? ?? 1,
      type: type,
      placeholderHandling: placeholderHandling,
      matcherConfigs: List<FieldMatcherConfig>.from((map['matcherConfigs']
                  as List<dynamic>?)
              ?.cast<Map<String, dynamic>>()
              .map<FieldMatcherConfig>((x) => FieldMatcherConfig.fromMap(x)) ??
          <FieldMatcherConfig>[]),
      extraMembers: extraMembersOf(map, _knownMembers, unparsedEnums: {
        'type': type,
        'placeholderHandling': placeholderHandling,
      }),
    );
  }

  factory Field.fromJson(String source) =>
      Field.fromMap(json.decode(source) as Map<String, dynamic>?);

  Field copyWith({
    String? uuid,
    String? name,
    String? valuePath,
    String? value,
    int? page,
    FieldType? type,
    PlaceholderHandling? placeholderHandling,
    List<FieldMatcherConfig>? matcherConfigs,
    Map<String, dynamic>? extraMembers,
  }) {
    return Field(
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      valuePath: valuePath ?? this.valuePath,
      value: value ?? this.value,
      page: page ?? this.page,
      type: type ?? this.type,
      placeholderHandling: placeholderHandling ?? this.placeholderHandling,
      matcherConfigs: matcherConfigs ?? this.matcherConfigs,
      extraMembers: extraMembers ?? this.extraMembers,
    );
  }

  Map<String, dynamic> toMap() {
    return withExtraMembers({
      'page': page,
      'valuePath': valuePath,
      'uuid': uuid,
      'type': type?.name,
      'matcherConfigs': matcherConfigs?.map((x) => x.toMap()).toList(),
      if (name?.isNotEmpty ?? false) 'name': name,
      if (value?.isNotEmpty ?? false) 'value': value,
      if (placeholderHandling != null &&
          placeholderHandling != PlaceholderHandling.Default)
        'placeholderHandling': placeholderHandling?.name,
    }, extraMembers);
  }

  String toJson() => json.encode(toMap());

  @override
  String toString() {
    return 'Field(uuid: $uuid, name: $name, valuePath: $valuePath, value: $value, page: $page, type: $type, placeholderHandling: $placeholderHandling, matcherConfigs: $matcherConfigs)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    final unOrdDeepEq = const DeepCollectionEquality.unordered().equals;

    return other is Field &&
        other.uuid == uuid &&
        other.name == name &&
        other.valuePath == valuePath &&
        other.value == value &&
        other.page == page &&
        other.type == type &&
        other.placeholderHandling == placeholderHandling &&
        unOrdDeepEq(other.matcherConfigs, matcherConfigs) &&
        extraMembersEqual(other.extraMembers, extraMembers);
  }

  @override
  int get hashCode {
    return uuid.hashCode ^
        name.hashCode ^
        valuePath.hashCode ^
        value.hashCode ^
        page.hashCode ^
        type.hashCode ^
        placeholderHandling.hashCode ^
        const ListEquality().hash(matcherConfigs) ^
        extraMembersHash(extraMembers);
  }

  String? uuid;
  String? name;
  String? valuePath;
  String? value;
  int page = 1;
  FieldType? type;
  PlaceholderHandling? placeholderHandling;
  List<FieldMatcherConfig>? matcherConfigs;

  /// JSON members this version of the model does not know, written back on save.
  /// See `extra_members.dart`.
  final Map<String, dynamic> extraMembers;

  BrowserFieldModelV1? convertToV1() {
    var displayName = name;
    var ffValue = value;
    var htmlName = '';
    var htmlId = '';
    var htmlType = Utilities.fieldTypeToFormFieldType(type ?? FieldType.Text);

    // Currently we can only have one custommatcher. If that changes and someone tries
    // to use this old version with a newer DB things will break so they will have to
    // upgrade again to fix it.
    final customMatcherConfig =
        matcherConfigs?.firstWhereOrNull((mc) => mc.customMatcher != null);
    if (customMatcherConfig != null) {
      htmlName =
          customMatcherConfig.customMatcher?.names.elementAtOrNull(0) ?? '';
      htmlId = customMatcherConfig.customMatcher?.ids.elementAtOrNull(0) ?? '';

      if (customMatcherConfig.customMatcher?.types != null) {
        htmlType = Utilities.formFieldTypeFromHtmlTypeOrFieldType(
            customMatcherConfig.customMatcher!.types.elementAtOrNull(0) ?? '',
            type ?? FieldType.Text);
      }
    }

    if (type == FieldType.Password && valuePath == 'Password') {
      displayName = 'KeePass password';
      htmlType = FormFieldType.PASSWORD;
      ffValue = '{PASSWORD}';
    } else if (type == FieldType.Text && valuePath == 'UserName') {
      displayName = 'KeePass username';
      htmlType = FormFieldType.USERNAME;
      ffValue = '{USERNAME}';
    }

    if (displayName?.isEmpty ?? true) {
      displayName = uuid;
    }

    if (ffValue != '') {
      return BrowserFieldModelV1(
        name: htmlName,
        displayName: displayName,
        value: ffValue,
        type: htmlType,
        fieldId: htmlId,
        page: page,
        placeholderHandling:
            (placeholderHandling ?? PlaceholderHandling.Default).name,
      );
    }
    return null;
  }
}
