import 'dart:convert';

import 'package:collection/collection.dart';

import 'package:kdbx/src/kee_vault_model/entry_matcher.dart';
import 'package:kdbx/src/kee_vault_model/enums.dart';
import 'package:kdbx/src/kee_vault_model/form_field_type.dart';

import 'field_matcher_config.dart';

class BrowserFieldModelV1 {
  BrowserFieldModelV1({
    this.displayName,
    this.name = '',
    this.type = FormFieldType.TEXT,
    this.fieldId = '',
    this.page = 0,
    this.placeholderHandling = 'Default',
    this.value = '',
  });

  factory BrowserFieldModelV1.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return BrowserFieldModelV1();
    }

    return BrowserFieldModelV1(
      displayName: map['displayName'] as String?,
      name: map['name'] as String?,
      type: map['type'] as String?,
      // Should have been persisted as id for KPRPC.plgx compatability but
      // PWA sometimes or always persists as fieldId by mistake.
      fieldId: map['id'] as String? ?? map['fieldId'] as String?,
      page: map['page'] as int? ?? -1,
      placeholderHandling: map['placeholderHandling'] as String?,
      value: map['value'] as String?,
    );
  }
  factory BrowserFieldModelV1.fromJson(String source) =>
      BrowserFieldModelV1.fromMap(json.decode(source) as Map<String, dynamic>?);

  String? displayName;
  String? name;
  String? type;
  String? fieldId;
  int page;
  String? placeholderHandling;
  String? value;

  @override
  // ignore: avoid_renaming_method_parameters
  bool operator ==(Object o) {
    if (identical(this, o)) {
      return true;
    }

    return o is BrowserFieldModelV1 &&
        o.displayName == displayName &&
        o.name == name &&
        o.type == type &&
        o.fieldId == fieldId &&
        o.page == page &&
        o.placeholderHandling == placeholderHandling &&
        o.value == value;
  }

  @override
  int get hashCode {
    return displayName.hashCode ^
        name.hashCode ^
        type.hashCode ^
        fieldId.hashCode ^
        page.hashCode ^
        placeholderHandling.hashCode ^
        value.hashCode;
  }

  BrowserFieldModelV1 copyWith({
    String? displayName,
    String? name,
    String? type,
    String? fieldId,
    int? page,
    String? placeholderHandling,
    String? value,
  }) {
    return BrowserFieldModelV1(
      displayName: displayName ?? this.displayName,
      name: name ?? this.name,
      type: type ?? this.type,
      fieldId: fieldId ?? this.fieldId,
      page: page ?? this.page,
      placeholderHandling: placeholderHandling ?? this.placeholderHandling,
      value: value ?? this.value,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'displayName': displayName,
      'name': name,
      'type': type,
      'id': fieldId,
      'page': page,
      'placeholderHandling': placeholderHandling,
      'value': value,
    };
  }

  String toJson() => json.encode(toMap());

  @override
  String toString() {
    return 'BrowserFieldModel(displayName: $displayName, name: $name, type: $type, fieldId: $fieldId, page: $page, placeholderHandling: $placeholderHandling, value: $value)';
  }
}

//TODO: delete all below when configv2 is working

// defaults...
// class BrowserFieldModel(
//                 String displayName: this.getBrowserFieldDisplayNameDefault(),
//                 String name: '',
//                 String type: this.getBrowserFieldTypeDefault(),
//                 String fieldId = '';
//                 int page = -1;
//                 String placeholderHandling: 'Default'

/*

for when outputting to json (persistence or kepassrpc):
$Password etc is old way of identifying the user and pass common fields in KeeWeb . probably useless now.

    getBrowserFieldDisplayNameDefault: function() {
        if (this.model.name === '$Password') return 'KeePass password';
        else if (this.model.name === '$UserName') return 'KeePass username';
        else return '';
    },

    getBrowserFieldTypeDefault: function() {
        if (this.model.name === '$Password') return 'FFTpassword';
        else if (this.model.name === '$UserName') return 'FFTusername';
        else return 'FFTtext';
    },
    */
