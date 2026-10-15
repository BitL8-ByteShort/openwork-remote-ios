import Foundation

public struct OpenCodeCursor: Codable, Sendable, Equatable {
  public let previous:String?
  public let next:String?
}
public struct OpenCodeProject: Codable, Sendable, Identifiable, Equatable {
  public struct Time: Codable, Sendable, Equatable { public let created:Double; public let updated:Double; public let active:Double; public let archived:Double? }
  public let id:String
  public let canonical:String
  public let name:String?
  public let sandboxes:[String]
  public let time:Time
  public var displayName:String { name ?? URL(fileURLWithPath:canonical).lastPathComponent }
}
public struct OpenCodeLocation: Codable, Sendable, Equatable { public let directory:String }
public struct OpenCodeSession: Codable, Sendable, Identifiable, Equatable {
  public struct Time: Codable, Sendable, Equatable { public let created:Double; public let updated:Double; public let idle:Double?; public let archived:Double? }
  public let id:String
  public let projectID:String
  public let parentID:String?
  public let title:String?
  public let location:OpenCodeLocation
  public let time:Time
}
public struct OpenCodeSessionPage: Decodable, Sendable { public let data:[OpenCodeSession]; public let cursor:OpenCodeCursor }
extension OpenCodeClient {
  public func projects() async throws -> [OpenCodeProject] {
    let result = try await decode([OpenCodeProject].self,segments:["api","project"])
    guard result.count <= 10_000, Set(result.map(\.id)).count == result.count,
      result.allSatisfy({ !$0.id.isEmpty && $0.id.utf8.count <= 2_048 &&
        $0.canonical.hasPrefix("/") && !$0.canonical.contains("\0") }) else { throw RemoteError.invalidResponse }
    return result
  }
  public func sessions(projectID:String,cursor:String?,search:String?) async throws -> OpenCodeSessionPage {
    guard !projectID.isEmpty, projectID.utf8.count <= 2_048,
      (search?.utf8.count ?? 0) <= 4_096 else { throw RemoteError.invalidResponse }
    var query = [URLQueryItem(name:"limit",value:"50")]
    if let cursor { query.append(URLQueryItem(name:"cursor",value:cursor)) }
    else {
      query.append(URLQueryItem(name:"project",value:projectID)); query.append(URLQueryItem(name:"order",value:"desc"))
      if let search, !search.isEmpty { query.append(URLQueryItem(name:"search",value:search)) }
    }
    let page = try await decode(OpenCodeSessionPage.self,segments:["api","session"],query:query)
    try page.cursor.validate()
    guard page.data.count <= 200, Set(page.data.map(\.id)).count == page.data.count,
      page.data.allSatisfy({ $0.projectID == projectID && !$0.id.isEmpty && $0.id.utf8.count <= 2_048 &&
        $0.location.directory.hasPrefix("/") && !$0.location.directory.contains("\0") }) else { throw RemoteError.invalidResponse }
    return page
  }
  public func session(id:String) async throws -> OpenCodeSession {
    struct Response: Decodable, Sendable { let data:OpenCodeSession }
    let result = try await decode(Response.self,segments:["api","session",id]).data
    guard result.id == id, !result.projectID.isEmpty,
      result.location.directory.hasPrefix("/"), !result.location.directory.contains("\0") else { throw RemoteError.invalidResponse }
    return result
  }
}
extension OpenCodeCursor {
  func validate() throws {
    guard [previous,next].compactMap({$0}).allSatisfy({ !$0.isEmpty && $0.utf8.count <= 16_384 }) else {
      throw RemoteError.invalidResponse
    }
  }
}
