import Foundation

public struct OpenCodeModelRef:Codable,Sendable,Equatable,Hashable {
  public let providerID:String
  public let id:String
  public let variant:String?
  public init(providerID:String,id:String,variant:String?=nil) throws {
    guard !providerID.isEmpty,!id.isEmpty,providerID.utf8.count<=1_024,id.utf8.count<=1_024,
      variant.map({!$0.isEmpty && $0.utf8.count<=256}) ?? true else{throw RemoteError.invalidResponse}
    self.providerID=providerID;self.id=id;self.variant=variant
  }
  /// OpenCode 2.0.29 switchModel treats nil and the literal default as the same selection.
  /// Preserve raw wire equality separately for identities and persistence.
  public var isDefaultVariant:Bool{variant==nil || OpenCodeIdentity.matches(variant,"default")}
  public static func sameSelection(_ a:Self?,_ b:Self?)->Bool{
    guard let a,let b else{return a==nil && b==nil}
    return OpenCodeIdentity.matches(a.providerID,b.providerID) && OpenCodeIdentity.matches(a.id,b.id) &&
      ((a.isDefaultVariant && b.isDefaultVariant) || OpenCodeIdentity.matches(a.variant,b.variant))
  }
  private enum CodingKeys:String,CodingKey{case providerID,id,variant}
  public init(from decoder:any Decoder)throws {
    let c=try decoder.container(keyedBy:CodingKeys.self)
    try self.init(providerID:c.decode(String.self,forKey:.providerID),id:c.decode(String.self,forKey:.id),variant:c.decodeIfPresent(String.self,forKey:.variant))
  }
  public static func ==(lhs:Self,rhs:Self)->Bool {
    OpenCodeIdentity.matches(lhs.providerID,rhs.providerID) && OpenCodeIdentity.matches(lhs.id,rhs.id) && OpenCodeIdentity.matches(lhs.variant,rhs.variant)
  }
  public func hash(into hasher:inout Hasher) {
    OpenCodeIdentity.hash(providerID,into:&hasher);OpenCodeIdentity.hash(id,into:&hasher)
    hasher.combine(variant != nil);if let variant{OpenCodeIdentity.hash(variant,into:&hasher)}
  }
}
public struct OpenCodeModel:Decodable,Sendable,Equatable {
  public struct Variant:Decodable,Sendable,Equatable{public let id:String}
  public struct Capabilities:Decodable,Sendable,Equatable{public let tools:Bool;public let input:[String];public let output:[String]}
  public let id:String
  public let modelID:String
  public let providerID:String
  public let name:String
  public let enabled:Bool
  public let status:String
  public let variants:[Variant]
  public let capabilities:Capabilities
  public var selectionKey:Data {
    var key=Data("\(providerID.utf8.count):".utf8)
    key.append(contentsOf:providerID.utf8);key.append(contentsOf:id.utf8);return key
  }
  public var selectable:Bool{enabled && ["alpha","beta","deprecated","active"].contains(status)}
  func accepts(_ ref:OpenCodeModelRef)->Bool {
    selectable && OpenCodeIdentity.matches(ref.providerID,providerID) && OpenCodeIdentity.matches(ref.id,id) &&
      (ref.isDefaultVariant || (ref.variant.map{variant in variants.contains{OpenCodeIdentity.matches($0.id,variant)}} ?? false))
  }
}
public enum OpenCodePermissionEffect:String,Codable,Sendable{case allow,deny,ask}
public struct OpenCodePermissionRule:Codable,Sendable,Equatable,Hashable {
  public let action:String
  public let resource:String
  public let effect:OpenCodePermissionEffect
  public init(action:String,resource:String,effect:OpenCodePermissionEffect)throws {
    guard action.utf8.count<=4_096,resource.utf8.count<=8_192,!action.contains("\0"),!resource.contains("\0") else{throw RemoteError.invalidResponse}
    self.action=action;self.resource=resource;self.effect=effect
  }
  public static func ==(lhs:Self,rhs:Self)->Bool {
    OpenCodeIdentity.matches(lhs.action,rhs.action) && OpenCodeIdentity.matches(lhs.resource,rhs.resource) && lhs.effect==rhs.effect
  }
  public func hash(into hasher:inout Hasher) {
    OpenCodeIdentity.hash(action,into:&hasher);OpenCodeIdentity.hash(resource,into:&hasher);hasher.combine(effect)
  }
}
public struct OpenCodeAgent:Decodable,Sendable,Identifiable,Equatable {
  public let id:String
  public let name:String
  public let description:String?
  public let model:OpenCodeModelRef?
  public let mode:String
  public let hidden:Bool
  public let permissions:[OpenCodePermissionRule]
  public var selectable:Bool{!hidden && ["primary","all"].contains(mode)}
}
public struct OpenCodePermissionRequest:Decodable,Sendable,Identifiable,Equatable {
  public let id:String
  public let sessionID:String
  public let action:String
  public let resources:[String]
  public let save:[String]?
  public let message:String?
  public static func ==(lhs:Self,rhs:Self)->Bool {
    OpenCodeIdentity.matches(lhs.id,rhs.id) && OpenCodeIdentity.matches(lhs.sessionID,rhs.sessionID) &&
      OpenCodeIdentity.matches(lhs.action,rhs.action) && OpenCodeIdentity.matches(lhs.resources,rhs.resources) &&
      OpenCodeIdentity.matches(lhs.save,rhs.save) && OpenCodeIdentity.matches(lhs.message,rhs.message)
  }
}
public struct OpenCodeSavedPermission:Decodable,Sendable,Identifiable,Equatable {
  public struct Time:Decodable,Sendable,Equatable{public let created:Double;public let updated:Double}
  public let id:String
  public let projectID:String
  public let action:String
  public let resource:String
  public let time:Time
}
public enum OpenCodePermissionDecision:String,Codable,Sendable{case once,always,reject}
public enum OpenCodePermissionResolution:Sendable{case confirmed,alreadyResolved}
private struct OpenCodeLocated<Value:Decodable&Sendable>:Decodable,Sendable{let location:OpenCodeLocation;let data:Value}

extension OpenCodeClient {
  func locationQuery(_ location:OpenCodeLocation)throws->[URLQueryItem] {
    try OpenCodeLocation.validate(location.directory)
    return [URLQueryItem(name:"location[directory]",value:location.directory)]
  }
  public func models(location:OpenCodeLocation) async throws -> [OpenCodeModel] {
    let result=try await decode(OpenCodeLocated<[OpenCodeModel]>.self,segments:["api","model"],query:locationQuery(location))
    guard result.location==location,result.data.count<=10_000,
      Set(result.data.map(\.selectionKey)).count==result.data.count,
      result.data.allSatisfy({!$0.id.isEmpty && !$0.providerID.isEmpty && $0.id.utf8.count<=1_024 && $0.providerID.utf8.count<=1_024 &&
        $0.name.utf8.count<=4_096 && $0.variants.count<=256 && $0.variants.allSatisfy({!$0.id.isEmpty && $0.id.utf8.count<=256})}) else{throw RemoteError.invalidResponse}
    return result.data
  }
  public func defaultModel(location:OpenCodeLocation) async throws -> OpenCodeModel? {
    struct Response:Decodable,Sendable{let location:OpenCodeLocation;let data:OpenCodeModel?}
    let result=try await decode(Response.self,segments:["api","model","default"],query:locationQuery(location))
    guard result.location==location else{throw RemoteError.conflict};return result.data
  }
  public func agents(location:OpenCodeLocation) async throws -> [OpenCodeAgent] {
    let result=try await decode(OpenCodeLocated<[OpenCodeAgent]>.self,segments:["api","agent"],query:locationQuery(location))
    guard result.location==location,result.data.count<=2_000,Set(result.data.map(\.id)).count==result.data.count,
      result.data.allSatisfy({!$0.id.isEmpty && $0.id.utf8.count<=1_024 && $0.permissions.count<=2_000}) else{throw RemoteError.invalidResponse}
    return result.data
  }
  public func setModel(target:OpenCodeTarget,model:OpenCodeModelRef,expectedModel:OpenCodeModelRef?) async throws -> OpenCodeSession {
    let before=try await verifyTarget(target)
    guard OpenCodeModelRef.sameSelection(before.model,expectedModel) else{throw RemoteError.conflict}
    let catalog=try await models(location:OpenCodeLocation(directory:target.directory))
    guard catalog.contains(where:{$0.accepts(model)}) else{throw RemoteError.invalidResponse}
    struct Body:Encodable{let model:OpenCodeModelRef}
    _ = try await data(segments:["api","session",target.sessionID,"model"],method:"POST",body:JSONEncoder().encode(Body(model:model)))
    let actual=try await session(id:target.sessionID)
    guard OpenCodeModelRef.sameSelection(actual.model,model),actual.projectID==target.projectID,OpenCodeIdentity.matches(actual.location.directory,target.directory) else{throw RemoteError.conflict}
    return actual
  }
  public func setAgent(target:OpenCodeTarget,agentID:String,expectedAgent:String?) async throws -> OpenCodeSession {
    let before=try await verifyTarget(target)
    guard before.agent==expectedAgent else{throw RemoteError.conflict}
    let catalog=try await agents(location:OpenCodeLocation(directory:target.directory))
    guard catalog.contains(where:{$0.id==agentID && $0.selectable}) else{throw RemoteError.invalidResponse}
    struct Body:Encodable{let agent:String}
    _ = try await data(segments:["api","session",target.sessionID,"agent"],method:"POST",body:JSONEncoder().encode(Body(agent:agentID)))
    let actual=try await session(id:target.sessionID)
    guard actual.agent==agentID,actual.projectID==target.projectID,OpenCodeIdentity.matches(actual.location.directory,target.directory) else{throw RemoteError.conflict}
    return actual
  }
  public func setSessionRules(target:OpenCodeTarget,rules:[OpenCodePermissionRule],expectedRules:[OpenCodePermissionRule]?) async throws -> OpenCodeSession {
    let before=try await verifyTarget(target)
    guard rules.count<=2_000 else{throw RemoteError.oversized}
    for rule in rules{_ = try OpenCodePermissionRule(action:rule.action,resource:rule.resource,effect:rule.effect)}
    guard before.permissions==expectedRules else{throw RemoteError.conflict}
    struct Body:Encodable{let permissions:[OpenCodePermissionRule]}
    _ = try await data(segments:["api","session",target.sessionID],method:"PATCH",body:JSONEncoder().encode(Body(permissions:rules)))
    let actual=try await session(id:target.sessionID)
    guard actual.permissions==rules,actual.projectID==target.projectID,OpenCodeIdentity.matches(actual.location.directory,target.directory) else{throw RemoteError.conflict}
    return actual
  }
  public func pendingPermissions(target:OpenCodeTarget) async throws -> [OpenCodePermissionRequest] {
    try validateTarget(target)
    struct Response:Decodable,Sendable{let data:[OpenCodePermissionRequest]}
    let result=try await decode(Response.self,segments:["api","session",target.sessionID,"permission"]).data
    guard result.count<=2_000,Set(result.map(\.id)).count==result.count,
      result.allSatisfy({$0.sessionID==target.sessionID && !$0.id.isEmpty && $0.id.utf8.count<=2_048 && $0.resources.count<=2_000}) else{throw RemoteError.invalidResponse}
    return result
  }
  public func replyPermission(target:OpenCodeTarget,request:OpenCodePermissionRequest,decision:OpenCodePermissionDecision) async throws -> OpenCodePermissionResolution {
    try await verifyTarget(target)
    guard request.sessionID==target.sessionID else{throw RemoteError.invalidResponse}
    let before=try await pendingPermissions(target:target)
    guard let actual=before.first(where:{$0.id==request.id}) else{return .alreadyResolved}
    guard actual==request else{throw RemoteError.conflict}
    if decision == .always,request.save?.isEmpty != false{throw RemoteError.invalidResponse}
    struct Body:Encodable{let decision:OpenCodePermissionDecision}
    do{
      _ = try await data(segments:["api","session",target.sessionID,"permission",request.id,"reply"],method:"POST",body:JSONEncoder().encode(Body(decision:decision)))
    }catch{
      // The request may have settled on either client. Never replay a different ID.
      if let after=try? await pendingPermissions(target:target),!after.contains(where:{$0.id==request.id}){return .alreadyResolved}
      throw RemoteError.outcomeUnknown
    }
    let after=try await pendingPermissions(target:target)
    guard !after.contains(where:{$0.id==request.id}) else{throw RemoteError.outcomeUnknown}
    return .confirmed
  }
  public func savedPermissions(target:OpenCodeTarget) async throws -> [OpenCodeSavedPermission] {
    try validateTarget(target)
    struct Response:Decodable,Sendable{let data:[OpenCodeSavedPermission]}
    let result=try await decode(Response.self,segments:["api","permission","saved"],query:[URLQueryItem(name:"projectID",value:target.projectID)]).data
    guard result.count<=10_000,result.allSatisfy({$0.projectID==target.projectID && !$0.id.isEmpty && $0.id.utf8.count<=2_048}) else{throw RemoteError.invalidResponse}
    return result
  }
  public func removeSavedPermission(target:OpenCodeTarget,id:String) async throws {
    try await verifyTarget(target)
    let before=try await savedPermissions(target:target)
    guard before.contains(where:{$0.id==id}) else{throw RemoteError.notFound}
    _ = try await data(segments:["api","permission","saved",id],method:"DELETE")
    let after=try await savedPermissions(target:target)
    guard !after.contains(where:{$0.id==id}) else{throw RemoteError.outcomeUnknown}
  }
}
