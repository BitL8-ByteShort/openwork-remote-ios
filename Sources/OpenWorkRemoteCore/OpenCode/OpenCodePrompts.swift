import Foundation

public struct OpenCodePromptNotSubmitted:Error,Sendable,Equatable {
  public let reason:RemoteError
  public init(reason:RemoteError){self.reason=reason}
}

/// Stable identity is persisted before admission. A failed response never creates a new ID.
public struct OpenCodePrompt:Codable,Sendable,Equatable,CustomStringConvertible,CustomDebugStringConvertible {
  public let id:String
  public let text:String
  public let resume:Bool
  public let files:[OpenCodePromptFile]
  public let skills:[String]
  public init(id:String="msg_"+UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased(),
              text:String,resume:Bool=true,files:[OpenCodePromptFile]=[],skills:[String]=[]) throws {
    guard text.utf8.count<=32_768,files.count<=4 else{throw RemoteError.oversized}
    for file in files{try file.validate()}
    guard files.reduce(0,{$0+$1.bytes})<=40*1_048_576 else{throw RemoteError.oversized}
    guard id.hasPrefix("msg_"),id.utf8.count<=256,
      id.unicodeScalars.allSatisfy({CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"}),
      !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !files.isEmpty || !skills.isEmpty,
      Set(files.map(\.id)).count==files.count,skills.count<=50,Set(skills.map(OpenCodeIdentity.key)).count==skills.count,
      skills.allSatisfy({!$0.isEmpty && $0.utf8.count<=2_048}) else{throw RemoteError.invalidResponse}
    self.id=id;self.text=text;self.resume=resume;self.files=files;self.skills=skills
  }
  private enum CodingKeys:String,CodingKey{case id,text,resume,files,skills}
  public init(from decoder:any Decoder)throws {
    let c=try decoder.container(keyedBy:CodingKeys.self)
    try self.init(id:c.decode(String.self,forKey:.id),text:c.decode(String.self,forKey:.text),resume:c.decode(Bool.self,forKey:.resume),
      files:c.decodeIfPresent([OpenCodePromptFile].self,forKey:.files) ?? [],skills:c.decodeIfPresent([String].self,forKey:.skills) ?? [])
  }
  var wireText:String{
    let original=text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? [] : [text]
    return (original+files.compactMap(\.stagedPath).map{"Attached file: `"+$0+"`"}).joined(separator:"\n")
  }
  func wireBody()throws->Data{
    struct File:Encodable{let uri:String;let name:String}
    struct Skill:Encodable{let id:String}
    struct Reference:Encodable{let name:String;let mime:String;let path:String}
    struct Metadata:Encodable{let displayText:String;let comments:[String];let attachments:[Reference]}
    struct Body:Encodable{let id:String;let text:String;let resume:Bool;let files:[File]?;let skills:[Skill]?;let metadata:Metadata?}
    let inline=try files.filter{$0.placement == .inline}.map{try File(uri:$0.inlineURI(),name:$0.name)}
    let staged=files.compactMap{file in file.stagedPath.map{Reference(name:file.name,mime:file.mime,path:$0)}}
    let body=Body(id:id,text:wireText,resume:resume,files:inline.isEmpty ? nil : inline,skills:skills.isEmpty ? nil : skills.map{Skill(id:$0)},
      metadata:staged.isEmpty ? nil : Metadata(displayText:text,comments:[],attachments:staged))
    let encoder=JSONEncoder();encoder.outputFormatting=[.withoutEscapingSlashes]
    let data=try encoder.encode(body)
    guard data.count<=56*1_048_576 else{throw RemoteError.oversized};return data
  }
  public static func ==(a:Self,b:Self)->Bool{
    OpenCodeIdentity.matches(a.id,b.id) && OpenCodeIdentity.matches(a.text,b.text) && a.resume==b.resume && a.files==b.files && OpenCodeIdentity.matches(a.skills,b.skills)
  }
  public var description:String{"OpenCodePrompt(<redacted>)"}
  public var debugDescription:String{description}
}

public struct OpenCodePromptAdmission:Decodable,Sendable,CustomStringConvertible {
  public struct Payload:Decodable,Sendable,Equatable {
    public let text:String
    public let hasAttachments:Bool
    public let files:[OpenCodeMaterializedFile]
    public let skillIDs:[String?]
    public let skillNames:[String?]
    let agentCount:Int
    private enum CodingKeys:String,CodingKey{case text,files,agents,skills}
    private struct Item:Decodable,Sendable {}
    public init(from decoder:any Decoder)throws {
      let c=try decoder.container(keyedBy:CodingKeys.self)
      text=try c.decode(String.self,forKey:.text)
      files=try c.decodeIfPresent([OpenCodeMaterializedFile].self,forKey:.files) ?? []
      let skills=try c.decodeIfPresent([OpenCodeSkillIdentity].self,forKey:.skills) ?? []
      skillIDs=skills.map(\.id);skillNames=skills.map(\.name)
      agentCount=try (c.decodeIfPresent([Item].self,forKey:.agents) ?? []).count
      guard files.count<=200,skillIDs.count<=200,agentCount<=200 else{throw RemoteError.invalidResponse}
      hasAttachments = !files.isEmpty || !skillIDs.isEmpty || agentCount>0
    }
    func matches(_ prompt:OpenCodePrompt)->Bool{
      let expected=prompt.files.filter{$0.placement == .inline}
      return OpenCodeIdentity.matches(text,prompt.wireText) && agentCount==0 && files.count==expected.count &&
        zip(files,expected).allSatisfy{$0.matches($1)} && skillIDs.count==prompt.skills.count &&
        zip(skillIDs,prompt.skills).allSatisfy{OpenCodeIdentity.matches($0,$1)}
    }
    public static func ==(a:Self,b:Self)->Bool{
      OpenCodeIdentity.matches(a.text,b.text) && a.files==b.files && a.agentCount==b.agentCount && a.skillIDs.count==b.skillIDs.count &&
        zip(a.skillNames,b.skillNames).allSatisfy{OpenCodeIdentity.matches($0,$1)} &&
        zip(a.skillIDs,b.skillIDs).allSatisfy{OpenCodeIdentity.matches($0,$1)}
    }
  }
  public let id:String
  public let sessionID:String
  public let type:String
  public let payload:Payload
  public func matches(_ prompt:OpenCodePrompt,sessionID:String)->Bool {
    OpenCodeIdentity.matches(id,prompt.id) && OpenCodeIdentity.matches(self.sessionID,sessionID) &&
      type=="user" && payload.matches(prompt)
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
  @discardableResult func verifyTarget(_ target:OpenCodeTarget) async throws -> OpenCodeSession {
    try validateTarget(target)
    let actual=try await session(id:target.sessionID)
    guard OpenCodeIdentity.matches(actual.projectID,target.projectID),OpenCodeIdentity.matches(actual.location.directory,target.directory),
      actual.time.archived==nil else{throw RemoteError.conflict}
    return actual
  }
  public func send(target:OpenCodeTarget,input:OpenCodePrompt) async throws -> OpenCodePromptAdmission {
    let request:URLRequest
    do{
      for file in input.files{guard file.target==target else{throw RemoteError.conflict}}
      let session=try await verifyTarget(target)
      if !input.files.isEmpty{
        for file in input.files where file.placement == .inline{guard file.fitsQualifiedInlineLimits else{throw RemoteError.oversized}}
        let model=try await effectiveAttachmentModel(session:session,target:target)
        guard input.files.allSatisfy({file in
          file.placement == .staged ? model.capabilities.tools : model.capabilities.input.contains(file.mime=="image/png" ? "image" : "pdf")
        }) else{throw RemoteError.conflict}
      }
      let info=try await requireQualifiedWrites()
      for file in input.files{guard try file.usesStagingRoot(info.paths.tmp) else{throw RemoteError.conflict}}
      let body=try input.wireBody();try Task.checkCancellation()
      request=try makeRequest(segments:["api","session",target.sessionID,"prompt"],method:"POST",body:body)
    }catch{
      let reason=(error as? RemoteError) ?? (error is CancellationError || error is OpenCodeRequestNotDispatched ? .cancelled : .unavailable)
      throw OpenCodePromptNotSubmitted(reason:reason)
    }
    let bytes:Data,status:Int
    do{(bytes,status)=try await transport.data(for:request,maximumBytes:OpenCodeResponseBudget.materializedPrompt.rawValue)}
    catch is OpenCodeRequestNotDispatched{throw OpenCodePromptNotSubmitted(reason:.cancelled)}
    catch{throw RemoteError.outcomeUnknown}
    // A failed/oversized acknowledgement may follow successful durable admission.
    guard bytes.count<=OpenCodeResponseBudget.materializedPrompt.rawValue else{throw RemoteError.outcomeUnknown}
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
    let result=try await decode(Response.self,segments:["api","session",target.sessionID,"inbox"],responseBudget:.materializedPrompt).data
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
