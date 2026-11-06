/// A URL pattern from a `regExUrls` / `regExBlockedUrls` array that Dart cannot
/// compile, for example one with .NET inline options such as `(?i)`.
///
/// It keeps the original source in [pattern] so that it is written back
/// unchanged on save. It never matches anything.
class UnparsableRegExp implements Pattern {
  UnparsableRegExp(this.pattern);

  /// The original regular expression source, as stored in the entry.
  final String pattern;

  @override
  Iterable<Match> allMatches(String string, [int start = 0]) => const <Match>[];

  @override
  Match? matchAsPrefix(String string, [int start = 0]) => null;

  @override
  bool operator ==(Object other) =>
      other is UnparsableRegExp && other.pattern == pattern;

  @override
  int get hashCode => pattern.hashCode;

  @override
  String toString() => 'UnparsableRegExp($pattern)';
}

/// Compiles a stored regular expression. A pattern Dart cannot compile
/// becomes an [UnparsableRegExp] instead of an error, so one bad pattern does
/// not make the whole entry configuration unreadable.
Pattern compileUrlPattern(String source) {
  try {
    return RegExp(source);
  } on FormatException {
    return UnparsableRegExp(source);
  }
}
