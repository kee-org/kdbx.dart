import 'dart:typed_data';

import 'package:kdbx/src/utils/byte_utils.dart';
import 'package:uuid/uuid.dart';

abstract class IGuidService {
  //String newGuid();
  String newGuidAsBase64();
}

class GuidService implements IGuidService {
  @override
  String newGuidAsBase64() {
    final buf = Uint8List(16);
    const Uuid().v4buffer(buf);
    return buf.encodeBase64();
  }
}
