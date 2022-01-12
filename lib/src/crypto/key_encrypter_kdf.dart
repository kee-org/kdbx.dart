import 'dart:convert';
import 'dart:typed_data';

import 'package:argon2_ffi_base/argon2_ffi_base.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:isolate/isolate_runner.dart';
import 'package:kdbx/kdbx.dart';
import 'package:kdbx/src/kdbx_var_dictionary.dart';
import 'package:kdbx/src/utils/byte_utils.dart';
import 'package:logging/logging.dart';
import 'package:pointycastle/export.dart';

final _logger = Logger('key_encrypter_kdf');

enum KdfType {
  Argon2d,
  Argon2id,
  Aes,
}

class KdfField<T> {
  KdfField(this.field, this.type);

  final String field;
  final ValueType<T> type;

  static final uuid = KdfField(r'$UUID', ValueType.typeBytes);
  static final salt = KdfField('S', ValueType.typeBytes);
  static final parallelism = KdfField('P', ValueType.typeUInt32);
  static final memory = KdfField('M', ValueType.typeUInt64);
  static final iterations = KdfField('I', ValueType.typeUInt64);
  static final version = KdfField('V', ValueType.typeUInt32);
  static final secretKey = KdfField('K', ValueType.typeBytes);
  static final assocData = KdfField('A', ValueType.typeBytes);
  static final rounds = KdfField('R', ValueType.typeInt64);

  static final fields = [
    salt,
    parallelism,
    memory,
    iterations,
    version,
    secretKey,
    assocData,
    rounds
  ];

  static void debugAll(VarDictionary dict) {
    _logger
        .fine('VarDictionary{\n${fields.map((f) => f.debug(dict)).join('\n')}');
  }

  T? read(VarDictionary dict) => dict.get(type, field);
  void write(VarDictionary dict, T value) => dict.set(type, field, value);
  VarDictionaryItem<T> item(T value) =>
      VarDictionaryItem<T>(field, type, value);

  String debug(VarDictionary dict) {
    final value = dict.get(type, field);
    final strValue = type == ValueType.typeBytes
        ? ByteUtils.toHexList(value as Uint8List?)
        : value;
    return '$field=$strValue';
  }
}

class KeyEncrypterKdf {
  KeyEncrypterKdf(this.argon2);

  static const kdfUuids = <String, KdfType>{
    '72Nt34wpREuR96mkA+MKDA==': KdfType.Argon2d,
    'nimLGVbbR3OyPfw+xvCh5g==': KdfType.Argon2id,
    'ydnzmmKKRGC/dA0IwYpP6g==': KdfType.Aes,
  };
  static KdbxUuid kdfUuidForType(KdfType type) {
    final uuid =
        kdfUuids.entries.firstWhere((element) => element.value == type).key;
    return KdbxUuid(uuid);
  }

  static KdfType kdfTypeFor(VarDictionary kdfParameters) {
    final uuid = KdfField.uuid.read(kdfParameters);
    if (uuid == null) {
      throw KdbxCorruptedFileException('No Kdf UUID');
    }
    final kdfUuid = base64.encode(uuid);
    try {
      final type = kdfUuids[kdfUuid];
      if (type != null) {
        return type;
      }
      throw KdbxCorruptedFileException('Invalid KDF UUID $kdfUuid');
    } catch (e) {
      throw KdbxCorruptedFileException(
          'Invalid KDF UUID ${uuid.encodeBase64()}');
    }
  }

  final Argon2? argon2;

  Future<Uint8List> encrypt(Uint8List key, VarDictionary kdfParameters) async {
    final kdfType = kdfTypeFor(kdfParameters);
    switch (kdfType) {
      case KdfType.Argon2d:
        _logger.fine('KDF = argon2d');
        return await encryptArgon2(key, kdfType, kdfParameters);
      case KdfType.Argon2id:
        _logger.fine('KDF = argon2id');
        // return await encryptArgon2(key, kdfType, kdfParameters);
        throw KdbxUnsupportedException(
            'Argon2id KDF not supported. Please ensure the Key Derivation Function in your KDBX is either Argon2 or Argon2d.');
      case KdfType.Aes:
        _logger.fine('KDF = aes');
        return await encryptAes(key, kdfParameters);
      default:
        throw KdbxUnsupportedException('unsupported KDF Type $kdfType.');
    }
  }

  Future<Uint8List> encryptArgon2(
      Uint8List key, KdfType kdfType, VarDictionary kdfParameters) async {
    return await argon2!.argon2Async(Argon2Arguments(
      key,
      KdfField.salt.read(kdfParameters)!,
      KdfField.memory.read(kdfParameters)! ~/ 1024,
      KdfField.iterations.read(kdfParameters)!,
      32,
      KdfField.parallelism.read(kdfParameters)!,
      kdfType == KdfType.Argon2id ? 2 : 0,
      KdfField.version.read(kdfParameters)!,
    ));
  }

  Future<Uint8List> encryptAes(
      Uint8List key, VarDictionary kdfParameters) async {
    final encryptionKey = KdfField.salt.read(kdfParameters)!;
    final rounds = KdfField.rounds.read(kdfParameters);
    assert(encryptionKey.length == 32);
    return await encryptAesAsync(EncryptAesArgs(encryptionKey, key, rounds));
  }

  static Future<Uint8List> encryptAesAsync(EncryptAesArgs args) async {
    if (KdbxFormat.dartWebWorkaround) {
      return _encryptAesSync(args);
    }
    final runner = await IsolateRunner.spawn();
    final s = Stopwatch()..start();
    try {
      _logger.finest('Starting encryptAes for ${args.rounds} '
          'rounds in isolate. ${args.encryptionKey.length} ${args.key.length}');
      return await runner.run(_encryptAesSync, args);
    } finally {
      _logger.finest('Done aes encrypt. ${s.elapsed}');
      await runner.kill();
    }
  }

  static Uint8List _encryptAesSync(EncryptAesArgs args) {
    final cipher = ECBBlockCipher(AESEngine())
      ..init(true, KeyParameter(args.encryptionKey));
    var out1 = Uint8List.fromList(args.key);
    var out2 = Uint8List(args.key.length);

    final rounds = args.rounds!;
    for (var i = 0; i < rounds; i++) {
      for (var j = 0; j < out1.lengthInBytes;) {
        j += cipher.processBlock(out1, j, out2, j);
      }
      final tmp = out1;
      out1 = out2;
      out2 = tmp;
    }
    return crypto.sha256.convert(out1).bytes as Uint8List;
  }
}

class EncryptAesArgs {
  EncryptAesArgs(this.encryptionKey, this.key, this.rounds);

  final Uint8List encryptionKey;
  final Uint8List key;
  final int? rounds;
}
