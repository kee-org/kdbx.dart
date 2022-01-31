import 'dart:typed_data';

import 'package:argon2_ffi_base/argon2_ffi_base.dart';

class KdfCache {
  Future<Uint8List?> getResult(Argon2Arguments a) async {
    return null;
  }

  Future<void> putItem(Argon2Arguments a, Uint8List result) async {
    return;
  }

  Future<String> argon2ArgumentsKey(Argon2Arguments a) async {
    return '';
  }
}
