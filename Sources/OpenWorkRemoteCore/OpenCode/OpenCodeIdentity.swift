import Foundation

/// Native directory/identifier bytes are opaque. Swift's normalized Unicode
/// equality can equate names that are different paths on a Linux filesystem.
public enum OpenCodeIdentity {
  public static func matches(_ lhs:String,_ rhs:String)->Bool{lhs.utf8.elementsEqual(rhs.utf8)}
  public static func key(_ value:String)->Data{Data(value.utf8)}
  static func matches(_ lhs:String?,_ rhs:String?)->Bool {
    switch (lhs,rhs){case (nil,nil):true;case let (a?,b?):matches(a,b);default:false}
  }
  static func matches(_ lhs:[String]?,_ rhs:[String]?)->Bool {
    switch (lhs,rhs){case (nil,nil):true;case let (a?,b?):a.count==b.count && zip(a,b).allSatisfy{matches($0,$1)};default:false}
  }
  static func hash(_ value:String,into hasher:inout Hasher){hasher.combine(Data(value.utf8))}
}
