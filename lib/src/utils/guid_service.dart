import 'package:uuid/uuid.dart';

abstract class IGuidService {
  String newGuid();
}

class GuidService implements IGuidService {
  @override
  String newGuid() {
    return Uuid().v4();
  }
}
