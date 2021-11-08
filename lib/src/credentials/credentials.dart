import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:kdbx/src/credentials/keyfile.dart';
import 'package:kdbx/src/crypto/protected_value.dart';
import 'package:kdbx/src/internal/extension_utils.dart';

abstract class CredentialsPart {
  Uint8List getBinary();
}

abstract class Credentials {
  factory Credentials(ProtectedValue password) =>
      Credentials.composite(password, null); //PasswordCredentials(password);
  factory Credentials.composite(ProtectedValue? password, Uint8List? keyFile) =>
      KeyFileComposite(
        password: password?.let((that) => PasswordCredentials(that)),
        keyFile: keyFile == null ? null : KeyFileCredentials(keyFile),
      );

  factory Credentials.fromHash(Uint8List hash) => HashCredentials(hash);

  void changePassword(ProtectedValue password);

  Uint8List getHash();
}

class PasswordCredentials implements CredentialsPart {
  PasswordCredentials(this._password);

  final ProtectedValue _password;

  @override
  Uint8List getBinary() {
    return _password.hash;
  }
}

class HashCredentials implements Credentials {
  HashCredentials(this.hash);

  Uint8List hash;

  @override
  Uint8List getHash() => hash;

  @override
  void changePassword(ProtectedValue password) {
    final buffer = password.hash;
    hash = crypto.sha256.convert(buffer).bytes as Uint8List;
  }
}
