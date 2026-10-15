import Foundation
import CryptoKit

public enum OpenCodeSharedData:String,Codable,CaseIterable,Hashable,Sendable{
  case conversation,projectContext,toolResults,photos,documents,skillInstructions
  public static let conversationContext:Set<Self>=[.conversation,.projectContext,.toolResults]
}
public enum OpenCodeSharingOperation:Sendable,Equatable{case message,attachment,formAnswer}
/// A reported configuration, not an attestation of a provider package's network route.
/// Raw settings, headers, URL credentials, paths and query strings are never retained.
public struct OpenCodeSharingDestination:Codable,Sendable,Hashable{
  public let connectionID:ConnectionID
  public let origin:String
  public let model:OpenCodeModelRef
  public let reportedEndpoint:String?
  public let configurationDigest:Data
  public var finalEndpointVerified:Bool{false}
  public var id:Data{
    let parts=[connectionID.rawValue.uuidString.lowercased(),origin,model.providerID,model.id,model.variant ?? "",configurationDigest.base64EncodedString()]
    return Data(SHA256.hash(data:(try? JSONEncoder().encode(parts)) ?? Data()))
  }
  public func validate()throws{
    guard configurationDigest.count==32,origin.utf8.count<=4_096,let url=URL(string:origin),
      try OpenCodeOrigin.canonical(url).absoluteString==origin,
      reportedEndpoint.map({$0.utf8.count<=4_096 && Self.authority($0)==$0}) ?? true else{throw RemoteError.invalidResponse}
  }
  public static func ==(a:Self,b:Self)->Bool{a.id==b.id}
  public func hash(into hasher:inout Hasher){hasher.combine(id)}
  private static func authority(_ raw:String)->String?{
    guard !raw.contains("${"),let c=URLComponents(string:raw),let scheme=c.scheme?.lowercased(),
      ["https","http"].contains(scheme),let host=c.host,!host.isEmpty else{return nil}
    var safe=URLComponents();safe.scheme=scheme;safe.host=host;safe.port=c.port
    return safe.string
  }
  fileprivate static func make(connection:OpenCodeConnection,ref:OpenCodeModelRef,raw:[String:Any])throws->Self{
    var configuration:[String:Any]=[:]
    for key in ["id","modelID","providerID","canonical","package","settings","headers","body","compatibility"]{
      if let value=raw[key]{configuration[key]=value}
    }
    let variant=(raw["variants"] as? [[String:Any]])?.first{OpenCodeIdentity.matches($0["id"] as? String,ref.variant)}
    if let variant{configuration["selectedVariant"]=variant}
    let settings=raw["settings"] as? [String:Any]
    let overlay=variant?["settings"] as? [String:Any]
    let endpoint=overlay?["baseURL"] ?? settings?["baseURL"]
    let bytes=try JSONSerialization.data(withJSONObject:configuration,options:[.sortedKeys,.withoutEscapingSlashes])
    let value=Self(connectionID:connection.id,origin:connection.origin.absoluteString,model:ref,
      reportedEndpoint:(endpoint as? String).flatMap(authority),configurationDigest:Data(SHA256.hash(data:bytes)))
    try value.validate();return value
  }
}
public protocol OpenCodeSharingReading:Sendable{
  func sharingDestination(target:OpenCodeTarget)async throws->OpenCodeSharingDestination
}
extension OpenCodeClient:OpenCodeSharingReading{
  public func sharingDestination(target:OpenCodeTarget)async throws->OpenCodeSharingDestination{
    let before=try await verifyTarget(target),location=OpenCodeLocation(directory:target.directory)
    var selected=before.model
    if selected==nil,let agent=before.agent{
      selected=try await agents(location:location).first{OpenCodeIdentity.matches($0.id,agent)}?.model
    }
    let bytes=try await data(segments:selected==nil ? ["api","model","default"]:["api","model"],query:locationQuery(location))
    guard let envelope=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],
      let wireLocation=envelope["location"] as? [String:Any],
      OpenCodeIdentity.matches(wireLocation["directory"] as? String,target.directory) else{throw RemoteError.conflict}
    let raw:[String:Any]
    if let selected{
      guard let catalog=envelope["data"] as? [[String:Any]],catalog.count<=10_000,
        let match=catalog.first(where:{OpenCodeIdentity.matches($0["id"] as? String,selected.id) && OpenCodeIdentity.matches($0["providerID"] as? String,selected.providerID)}) else{throw RemoteError.unavailable}
      raw=match
    }else{
      guard let model=envelope["data"] as? [String:Any] else{throw RemoteError.unavailable};raw=model
    }
    let model=try JSONDecoder().decode(OpenCodeModel.self,from:JSONSerialization.data(withJSONObject:raw))
    let ref=try selected ?? OpenCodeModelRef(providerID:model.providerID,id:model.id)
    guard model.accepts(ref) else{throw RemoteError.unavailable}
    let after=try await verifyTarget(target)
    guard OpenCodeModelRef.sameSelection(before.model,after.model),OpenCodeIdentity.matches(before.agent,after.agent) else{throw RemoteError.conflict}
    return try OpenCodeSharingDestination.make(connection:connection,ref:ref,raw:raw)
  }
}
