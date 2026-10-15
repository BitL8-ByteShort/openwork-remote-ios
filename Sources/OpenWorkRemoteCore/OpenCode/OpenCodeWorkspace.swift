import Foundation
import CryptoKit

public struct OpenCodeWorkspaceInfo:Decodable,Sendable,Equatable {
  public struct Branch:Decodable,Sendable,Equatable{public let current:String?;public let `default`:String?}
  public let provider:String?
  public let branch:Branch
}
public struct OpenCodeChange:Decodable,Sendable,Equatable,Identifiable {
  public enum Status:String,Decodable,Sendable{case added,deleted,modified}
  public let file:String
  public let additions:Int
  public let deletions:Int
  public let status:Status
  public var id:Data{Data(file.utf8)}
  fileprivate func validate()throws{
    guard !file.isEmpty,file.utf8.count<=8_192,!file.contains("\0"),additions>=0,deletions>=0 else{throw RemoteError.invalidResponse}
  }
}
public struct OpenCodeWorkingDiff:Decodable,Sendable,Equatable,Identifiable {
  public let file:String
  public let patch:String
  public let additions:Int
  public let deletions:Int
  public let status:OpenCodeChange.Status
  public var id:Data{Data(file.utf8)}
  fileprivate func validate()throws{
    guard !file.isEmpty,file.utf8.count<=8_192,!file.contains("\0"),additions>=0,deletions>=0 else{throw RemoteError.invalidResponse}
    guard patch.utf8.count<=1_048_576 else{throw RemoteError.oversized}
  }
}
/// Registered native instructions. Reading a skill never invokes it.
public struct OpenCodeSkill:Codable,Sendable,Equatable,Identifiable {
  public let id:String
  public let name:String
  public let description:String?
  public let path:String
  public let content:String
  public let autoinvoke:Bool?
  public let fingerprint:String
  private enum CodingKeys:String,CodingKey{case id,name,description,path,content,autoinvoke}
  public init(from decoder:any Decoder)throws{
    let c=try decoder.container(keyedBy:CodingKeys.self)
    id=try c.decode(String.self,forKey:.id);name=try c.decode(String.self,forKey:.name)
    description=try c.decodeIfPresent(String.self,forKey:.description);path=try c.decode(String.self,forKey:.path)
    content=try c.decode(String.self,forKey:.content);autoinvoke=try c.decodeIfPresent(Bool.self,forKey:.autoinvoke)
    guard !id.isEmpty,id.utf8.count<=2_048,!name.isEmpty,name.utf8.count<=4_096,
      (description?.utf8.count ?? 0)<=32_768,path.hasPrefix("/"),path.utf8.count<=8_192,!path.contains("\0") else{throw RemoteError.invalidResponse}
    guard content.utf8.count<=1_048_576 else{throw RemoteError.oversized}
    var material=Data()
    for field in [id,name,description ?? "",path,content,autoinvoke==true ? "true":"false"]{
      material.append(Data((String(field.utf8.count)+"\n").utf8));material.append(Data(field.utf8))
    }
    fingerprint=SHA256.hash(data:material).map{String(format:"%02x",$0)}.joined()
  }
}
public protocol OpenCodeWorkspaceServing:Sendable {
  func workspaceInfo(location:OpenCodeLocation)async throws->OpenCodeWorkspaceInfo
  func workspaceChanges(location:OpenCodeLocation)async throws->[OpenCodeChange]
  func workspaceDiff(location:OpenCodeLocation)async throws->[OpenCodeWorkingDiff]
  func skills(location:OpenCodeLocation)async throws->[OpenCodeSkill]
}
private struct NativeWorkspaceResponse<Value:Decodable&Sendable>:Decodable,Sendable{let location:OpenCodeLocation;let data:Value}
extension OpenCodeClient:OpenCodeWorkspaceServing {
  public func workspaceInfo(location:OpenCodeLocation)async throws->OpenCodeWorkspaceInfo{
    let response=try await decode(NativeWorkspaceResponse<OpenCodeWorkspaceInfo>.self,segments:["api","vcs"],query:locationQuery(location))
    guard response.location==location else{throw RemoteError.conflict}
    let value=response.data
    guard value.provider.map({!$0.isEmpty && $0.utf8.count<=256}) ?? true,
      [value.branch.current,value.branch.default].compactMap({$0}).allSatisfy({$0.utf8.count<=2_048 && !$0.contains("\0")}) else{throw RemoteError.invalidResponse}
    return value
  }
  public func workspaceChanges(location:OpenCodeLocation)async throws->[OpenCodeChange]{
    let response=try await decode(NativeWorkspaceResponse<[OpenCodeChange]>.self,segments:["api","vcs","status"],query:locationQuery(location))
    guard response.location==location else{throw RemoteError.conflict}
    guard response.data.count<=10_000,Set(response.data.map(\.id)).count==response.data.count else{throw RemoteError.oversized}
    for row in response.data{try row.validate()};return response.data
  }
  public func workspaceDiff(location:OpenCodeLocation)async throws->[OpenCodeWorkingDiff]{
    var query=try locationQuery(location);query.append(URLQueryItem(name:"mode",value:"working"))
    let response=try await decode(NativeWorkspaceResponse<[OpenCodeWorkingDiff]>.self,segments:["api","vcs","diff"],query:query)
    guard response.location==location else{throw RemoteError.conflict}
    guard response.data.count<=10_000,Set(response.data.map(\.id)).count==response.data.count else{throw RemoteError.oversized}
    for row in response.data{try row.validate()};return response.data
  }
  public func skills(location:OpenCodeLocation)async throws->[OpenCodeSkill]{
    let response=try await decode(NativeWorkspaceResponse<[OpenCodeSkill]>.self,segments:["api","skill"],query:locationQuery(location),responseBudget:.skillCatalog)
    guard response.location==location else{throw RemoteError.conflict}
    guard response.data.count<=10_000,Set(response.data.map{OpenCodeIdentity.key($0.id)}).count==response.data.count else{throw RemoteError.invalidResponse}
    return response.data
  }
}
