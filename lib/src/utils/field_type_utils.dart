import 'package:kdbx/src/kee_vault_model/enums.dart';
import 'package:kdbx/src/kee_vault_model/form_field_type.dart';
import 'package:kdbx/src/kee_vault_model/kee_vault_model.dart';

class Utilities {
  static String formFieldTypeToHtmlType(String fft) {
    if (fft == FormFieldType.PASSWORD) {
      return 'password';
    }
    if (fft == FormFieldType.SELECT) {
      return 'select-one';
    }
    if (fft == FormFieldType.RADIO) {
      return 'radio';
    }
    if (fft == FormFieldType.CHECKBOX) {
      return 'checkbox';
    }
    return 'text';
  }

  static FieldType formFieldTypeToFieldType(String fft) {
    FieldType type = FieldType.Text;
    if (fft == FormFieldType.PASSWORD) {
      type = FieldType.Password;
    } else if (fft == FormFieldType.SELECT) {
      type = FieldType.Existing;
    } else if (fft == FormFieldType.RADIO) {
      type = FieldType.Existing;
    } else if (fft == FormFieldType.USERNAME) {
      type = FieldType.Text;
    } else if (fft == FormFieldType.CHECKBOX) {
      type = FieldType.Toggle;
    }
    return type;
  }

  static String fieldTypeToDisplay(FieldType type, bool titleCase) {
    String typeD = 'Text';
    if (type == FieldType.Password) {
      typeD = 'Password';
    } else if (type == FieldType.Existing) {
      typeD = 'Existing';
    } else if (type == FieldType.Text) {
      typeD = 'Text';
    } else if (type == FieldType.Toggle) {
      typeD = 'Toggle';
    }
    if (!titleCase) {
      return typeD.toLowerCase();
    }
    return typeD;
  }

  static String fieldTypeToHtmlType(FieldType ft) {
    switch (ft) {
      case FieldType.Password:
        return 'password';
      case FieldType.Existing:
        return 'radio';
      case FieldType.Toggle:
        return 'checkbox';
      default:
        return 'text';
    }
  }

  static String fieldTypeToFormFieldType(FieldType ft) {
    switch (ft) {
      case FieldType.Password:
        return FormFieldType.PASSWORD;
      case FieldType.Existing:
        return FormFieldType.RADIO;
      case FieldType.Toggle:
        return FormFieldType.CHECKBOX;
      default:
        return FormFieldType.TEXT;
    }
  }

  // Assumes funky Username type has already been determined so all textual stuff is type text by now
  static String formFieldTypeFromHtmlTypeOrFieldType(String t, FieldType ft) {
    switch (t) {
      case 'password':
        return FormFieldType.PASSWORD;
      case 'radio':
        return FormFieldType.RADIO;
      case 'checkbox':
        return FormFieldType.CHECKBOX;
      case 'select-one':
        return FormFieldType.SELECT;
      default:
        return Utilities.fieldTypeToFormFieldType(ft);
    }
  }
}
