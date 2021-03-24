import 'dart:convert';

enum FieldStorage { CUSTOM, JSON, BOTH }

class FormFieldType {
  static const String USERNAME = 'FFTusername';
  static const String PASSWORD = 'FFTpassword';
  static const String TEXT = 'FFTtext';
  static const String RADIO = 'FFTradio';
  static const String CHECKBOX = 'FFTcheckbox';
  static const String SELECT = 'FFTselect';
}

class BrowserFieldModel {
  BrowserFieldModel({
    this.displayName,
    this.name,
    this.type,
    this.fieldId,
    this.page,
    this.placeholderHandling,
    this.value,
  });

  factory BrowserFieldModel.fromMap(Map<String, dynamic> map) {
    if (map == null) {
      return null;
    }

    return BrowserFieldModel(
      displayName: map['displayName'] as String,
      name: map['name'] as String,
      type: map['type'] as String,
      fieldId: map['id'] as String,
      page: map['page'] as int,
      placeholderHandling: map['placeholderHandling'] as String,
      value: map['value'] as String,
    );
  }
  factory BrowserFieldModel.fromJson(String source) =>
      BrowserFieldModel.fromMap(json.decode(source) as Map<String, dynamic>);

  String displayName;
  String name = '';
  String type = FormFieldType.TEXT;
  String fieldId = '';
  int page = 0;
  String placeholderHandling = 'Default';
  String value = '';

  @override
  // ignore: avoid_renaming_method_parameters
  bool operator ==(Object o) {
    if (identical(this, o)) {
      return true;
    }

    return o is BrowserFieldModel &&
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

  BrowserFieldModel copyWith({
    String displayName,
    String name,
    String type,
    String fieldId,
    int page,
    String placeholderHandling,
    String value,
  }) {
    return BrowserFieldModel(
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