import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

abstract class StringValue {
  /// retrieves the (decrypted) stored value.
  String getText();
}

class PlainValue implements StringValue {
  PlainValue(this.text);

  final String text;

  @override
  String getText() {
    return text;
  }

  @override
  String toString() {
    return 'PlainValue{text: $text}';
  }

  @override
  bool operator ==(dynamic other) => other is PlainValue && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

class ProtectedValue extends PlainValue {
  ProtectedValue(String text) : super(text);

  factory ProtectedValue.fromString(String value) {
    return ProtectedValue(value);
  }

  factory ProtectedValue.fromBinary(Uint8List value) {
    return ProtectedValue.fromString(utf8.decode(value));
  }
  Uint8List get binaryValue => utf8.encode(text) as Uint8List;

  Uint8List get hash => sha256.convert(binaryValue).bytes as Uint8List;
}

/*
We don't need to implement this protection and doing so causes typical kdbx files to take upwards of 5 seconds to open, with 90% of all processing time involved with secure random number generation. In future, if Dart ever supports finalisers or similar, we could zero this value but until then all other uses of the value within the process will invalidate the protection anyway (including the read/write kdbx operations of course). The performance could be improved if Dart were to ever offer access to a stream of secure random data rather than requiring us to pick away at one integer at a time.

We still call these ProtectedValues for the time being since that's in line with the expectations of library consumers but with no real protection of note, we could consider renaming in future (although as per below the same can be said for the original implementation).

Operating systems ensure other processes won't have access to the data we write in memory when that memory is reassigned after we're finished with it. We assume that this holds during any attack we can practically defend against. This leaves only the question of memory access from within our own process.

Other kdbx implementations utilise XOR stream ciphers but we can trivially break these by using a known plain text attack if we re-use the key for a different ProtectedValue so they only work because a new key is created every time.

Regardless, the real threat to the kdbx ProtectedValue concept is that the key is stored in memory (probably predictably and very closely next to) the "encrypted" value. Thus we conclude that all valid threats against an "UnProtectedValue" are only trivially more complex against a "ProtectedValue". Such threats include bugs in Dart or in our own code as well as Spectre-class attacks or exploitation of O/S kernel vulnerabilities. NB: In Windows, ProtectedStrings operate using a mechanism that keeps the key separate, albeit entirely accessible to a suitably motivated attacker who has access to the KeePass process memory. In that situation, the security benefit may be high enough to justify the additional cost, although that's still very much open for debate.

Isolate heaps can't reference each other so there may be some future benefit from keeping the Protected values encrypted while reading and writing the kdbx files in a separate isolate, and only decrypting them in the UI isolate when the user performs an operation that requires it. Still, if an attacker can access the memory in the UI isolate, it's infeasible that we could stop them from decrypting the kdbx file from scratch so this is almost certainly pointless.

*/
// class ProtectedValue implements StringValue {
//   ProtectedValue(this._value, this._salt);

//   factory ProtectedValue.fromString(String value) {
//     final valueBytes = utf8.encode(value) as Uint8List;
//     return ProtectedValue.fromBinary(valueBytes);
//   }

//   factory ProtectedValue.fromBinary(Uint8List value) {
//     final salt = _randomBytes(value.length);
//     //final salt = Uint8List(value.length);
//     return ProtectedValue(_xor(value, salt), salt);
//   }

//   static final random = Random.secure();

//   final Uint8List _value;
//   final Uint8List _salt;

//   Uint8List get binaryValue => _xor(_value, _salt);

//   Uint8List get hash => sha256.convert(binaryValue).bytes as Uint8List;

//   static Uint8List _randomBytes(int length) {
//     return Uint8List.fromList(
//         List.generate(length, (i) => random.nextInt(0xff)));
//   }

//   static Uint8List _xor(Uint8List a, Uint8List b) {
//     assert(a.length == b.length);
//     final ret = Uint8List(a.length);
//     for (var i = 0; i < a.length; i++) {
//       ret[i] = a[i] ^ b[i];
//     }
//     return ret;
//   }

//   @override
//   String getText() {
//     return utf8.decode(binaryValue);
//   }

//   @override
//   bool operator ==(dynamic other) =>
//       other is ProtectedValue && other.getText() == getText();

//   int _hashCodeCached;

//   @override
//   int get hashCode => _hashCodeCached ??= getText().hashCode;

//   @override
//   String toString() {
//     return 'ProtectedValue{${base64.encode(hash)}}';
//   }
// }
