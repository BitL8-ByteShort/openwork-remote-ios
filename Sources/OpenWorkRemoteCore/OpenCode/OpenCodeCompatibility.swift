public enum CompatibilityStatus: Sendable, Equatable { case qualified, unverified, incompatible }
public enum OpenCodeCompatibility {
  /// An inspected patch version is a profile, not a promise about every v2 schema.
  public static func evaluate(version: String) -> CompatibilityStatus {
    if version == "2.0.29" { return .qualified }
    if version.hasPrefix("1.") { return .incompatible }
    return .unverified
  }
}
