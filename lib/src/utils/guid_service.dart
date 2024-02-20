import 'package:uuid/uuid.dart';

abstract class IGuidService {
  String newGuid();
}

class GuidService implements IGuidService {
  @override
  String newGuid() {
    return const Uuid().v4();
  }
}
