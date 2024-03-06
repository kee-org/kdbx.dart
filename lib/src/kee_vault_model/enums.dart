enum BrowserAutoFillBehaviour {
  Default,
  AlwaysAutoFill,
  NeverAutoSubmit,
  AlwaysAutoFillNeverAutoSubmit,
  AlwaysAutoFillAlwaysAutoSubmit,
  NeverAutoFillNeverAutoSubmit
}

enum MatchAccuracy { Exact, Hostname, Domain }

enum FieldStorage { CUSTOM, JSON, BOTH }

enum FieldType { Text, Password, Existing, Toggle, Otp, SomeChars }

enum FieldMatcherType {
  Custom,
  UsernameDefaultHeuristic,
  PasswordDefaultHeuristic,
}

enum EntryMatcherType {
  Custom,
  Hide,
  Url, // magic type that uses primary URL + the 4 URL data arrays and current urlmatchconfig to determine a match
}

enum MatchAction { TotalMatch, TotalBlock, WeightedMatch, WeightedBlock }

enum MatcherLogic { Client, All, Any }

enum PlaceholderHandling { Default, Enabled, Disabled }
