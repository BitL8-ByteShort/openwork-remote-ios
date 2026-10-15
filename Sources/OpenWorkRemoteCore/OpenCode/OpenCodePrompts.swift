import Foundation

/// Stable identity is persisted before admission. A failed response never creates a new ID.
public struct OpenCodePrompt:Codable,Sendable,Equatable,CustomStringConvertible,CustomDebugStringConvertible {
  public let id:String
  public let text:String
  public let resume:Bool
  public init(id:String="msg_"+UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased(),
              text:String,resume:Bool=true) throws {
    guard text.utf8.count<=32_768 else{throw RemoteError.oversized}
    guard id.hasPrefix("msg_"),id.utf8.count<=256,
      id.unicodeScalars.allSatisfy({CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"}),
      !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{throw RemoteError.invalidResponse}
    self.id=id;self.text=text;self.resume=resume
  }
  private enum CodingKeys:String,CodingKey{case id,text,resume}
  public init(from decoder:any Decoder)throws {
    let c=try decoder.container(keyedBy:CodingKeys.self)
    try self.init(id:c.decode(String.self,forKey:.id),text:c.decode(String.self,forKey:.text),resume:c.decode(Bool.self,forKey:.resume))
  }
  public var description:String{"OpenCodePrompt(<redacted>)"}
  public var debugDescription:String{description}
}

public struct OpenCodePromptAdmission:Decodable,Sendable,CustomStringConvertible {
  public struct Payload:Decodable,Sendable {
    public let text:String
    public let hasAttachments:Bool
    private enum CodingKeys:String,CodingKey{case text,files,agents,skills}
    private struct Item:Decodable,Sendable {}
    public init(from decoder:any Decoder)throws {
      let c=try decoder.container(keyedBy:CodingKeys.self)
      text=try c.decode(String.self,forKey:.text)
      hasAttachments=try [.files,.agents,.skills].contains { key in
        !(try c.decodeIfPresent([Item].self,forKey:key) ?? []).isEmpty
      }
    }
  }
  public let id:String
  public let sessionID:String
  public let type:String
  public let payload:Payload
  public func matches(_ prompt:OpenCodePrompt,sessionID:String)->Bool {
    id==prompt.id && self.sessionID==sessionID && type=="user" && payload.text==prompt.text && !payload.hasAttachments
  }
  public var description:String{"OpenCodePromptAdmission(<redacted>)"}
}

public struct OpenCodeInboxItem:Decodable,Sendable {
  public let id:String
  public let sessionID:String
  public let type:String
  public let user:OpenCodePromptAdmission?
  private enum CodingKeys:String,CodingKey{case id,sessionID,type}
  public init(from decoder:any Decoder)throws {
    let c=try decoder.container(keyedBy:CodingKeys.self)
    id=try c.decode(String.self,forKey:.id);sessionID=try c.decode(String.self,forKey:.sessionID)
    type=try c.decode(String.self,forKey:.type)
    user=type=="user" ? try OpenCodePromptAdmission(from:decoder) : nil
  }
}

extension OpenCodeClient {
  func validateTarget(_ target:OpenCodeTarget) throws {
    guard target.connectionID==connection.id,!target.projectID.isEmpty,
      target.projectID.utf8.count<=2_048,target.sessionID.hasPrefix("ses"),target.sessionID.utf8.count<=2_048 else{
      throw RemoteError.invalidResponse
    }
    try OpenCodeLocation.validate(target.directory)
  }
  func verifyTarget(_ target:OpenCodeTarget) async throws {
    try validateTarget(target)
    let actual=try await session(id:target.sessionID)
    guard actual.projectID==target.projectID,actual.location.directory==target.directory,
      actual.time.archived==nil else{throw RemoteError.conflict}
  }
  public func send(target:OpenCodeTarget,input:OpenCodePrompt) async throws -> OpenCodePromptAdmission {
    try await verifyTarget(target)
    try await requireQualifiedWrites()
    let request=try makeRequest(segments:["api","session",target.sessionID,"prompt"],method:"POST",body:JSONEncoder().encode(input))
    let bytes:Data,status:Int
    do{(bytes,status)=try await transport.data(for:request)}
    catch{throw RemoteError.outcomeUnknown}
    // A failed/oversized acknowledgement may follow successful durable admission.
    guard bytes.count<=8_388_608 else{throw RemoteError.outcomeUnknown}
    try checkStatus(status)
    struct Response:Decodable{let data:OpenCodePromptAdmission}
    let result:OpenCodePromptAdmission
    do{result=try JSONDecoder().decode(Response.self,from:bytes).data}
    catch{throw RemoteError.outcomeUnknown}
    guard result.matches(input,sessionID:target.sessionID) else{throw RemoteError.conflict}
    return result
  }
  public func inbox(target:OpenCodeTarget) async throws -> [OpenCodeInboxItem] {
    try validateTarget(target)
    struct Response:Decodable,Sendable{let data:[OpenCodeInboxItem]}
    let result=try await decode(Response.self,segments:["api","session",target.sessionID,"inbox"]).data
    guard result.count<=10_000,Set(result.map(\.id)).count==result.count,
      result.allSatisfy({$0.sessionID==target.sessionID && !$0.id.isEmpty}) else{throw RemoteError.invalidResponse}
    return result
  }
  public func activeSessions() async throws -> Set<String> {
    struct Active:Decodable,Sendable{let type:String}
    struct Response:Decodable,Sendable{let data:[String:Active]}
    let result=try await decode(Response.self,segments:["api","session","active"]).data
    guard result.count<=10_000,result.allSatisfy({$0.key.utf8.count<=2_048 && $0.value.type=="running"}) else{throw RemoteError.invalidResponse}
    return Set(result.keys)
  }
  public func interrupt(target:OpenCodeTarget) async throws -> Bool {
    try await verifyTarget(target)
    let bytes=try await data(segments:["api","session",target.sessionID,"interrupt"],method:"POST")
    struct Response:Decodable{let interrupted:Bool}
    guard let result=try? JSONDecoder().decode(Response.self,from:bytes) else{throw RemoteError.outcomeUnknown}
    return result.interrupted
  }
}
