import 'dart:convert';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

final _logger = Logger('protected_salt_generator');

class ProtectedSaltGenerator {
  factory ProtectedSaltGenerator(Uint8List key) {
    final hash = sha256.convert(key).bytes as Uint8List;
    final cipher = Salsa20Engine()
      ..init(false, ParametersWithIV(KeyParameter(hash), salsaNonce));
    return ProtectedSaltGenerator._(cipher);
  }
  factory ProtectedSaltGenerator.chacha20(Uint8List key) {
    return ChachaProtectedSaltGenerator.create(key); // Chacha20();
  }

  ProtectedSaltGenerator._(this._cipher);

  static final salsaNonce =
      Uint8List.fromList([0xE8, 0x30, 0x09, 0x4B, 0x97, 0x20, 0x5D, 0x2A]);
  final StreamCipher _cipher;

  String decryptBase64(String protectedValue) {
    final bytes = base64.decode(protectedValue);
    if (bytes.isEmpty) {
      _logger.warning('decoded base64 data has length 0');
      return null;
    }
    final result = _cipher.process(bytes);
    final decrypted = utf8.decode(result);
    return decrypted;
  }

  String encryptToBase64(String plainValue) {
    final encrypted = _cipher.process(utf8.encode(plainValue) as Uint8List);
    return base64.encode(encrypted);
  }
}

class ChachaProtectedSaltGenerator extends ProtectedSaltGenerator {
  ChachaProtectedSaltGenerator._(StreamCipher state) : super._(state);

  factory ChachaProtectedSaltGenerator.create(Uint8List key) {
    final hash = sha512.convert(key);
    final secretKey = hash.bytes.sublist(0, 32);
    final nonce = hash.bytes.sublist(32, 32 + 12);

    final chaCha = ChaCha7539Engine();
    chaCha.init(
        true,
        ParametersWithIV(
            KeyParameter(secretKey as Uint8List), nonce as Uint8List));
    return ChachaProtectedSaltGenerator._(chaCha);
  }
}
