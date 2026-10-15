import Foundation
import CryptoKit

public struct OpenCodeToolFileReference:Sendable,Equatable {
  public let uri:String
  public let mime:String
  public static func ==(a:Self,b:Self)->Bool{OpenCodeIdentity.matches(a.uri,b.uri) && a.mime==b.mime}
}
public struct OpenCodeResultSource:Codable,Sendable,Equatable {
  public enum Kind:String,Codable,Sendable{case selectedProjectFile,tool,snapshot}
  public let kind:Kind
  public let messageID:String?
  public let contentIndex:Int?
  public let fileIndex:Int?
  public init(messageID:String?=nil,contentIndex:Int?=nil,fileIndex:Int?=nil,kind:Kind?=nil){self.messageID=messageID;self.contentIndex=contentIndex;self.fileIndex=fileIndex;self.kind=kind ?? (messageID==nil ? .selectedProjectFile:.tool)}
  public static func ==(a:Self,b:Self)->Bool{a.kind==b.kind && OpenCodeIdentity.matches(a.messageID,b.messageID) && a.contentIndex==b.contentIndex && a.fileIndex==b.fileIndex}
}
public struct OpenCodeResultFile:Codable,Sendable,Identifiable,Equatable,Hashable {
  public let target:OpenCodeTarget
  public let relativePath:String
  public let source:OpenCodeResultSource
  public var name:String{String(relativePath.split(separator:"/").last!)}
  public let id:String
  private static func identity(target:OpenCodeTarget,relativePath:String)->String{
    var data=Data()
    for value in [target.connectionID.rawValue.uuidString,target.projectID,target.sessionID,target.directory,relativePath]{
      data.append(Data("\(value.utf8.count):".utf8));data.append(contentsOf:value.utf8)
    }
    return SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
  }
  public init(relativePath:String,target:OpenCodeTarget,source:OpenCodeResultSource=OpenCodeResultSource())throws{
    try Self.validatePath(relativePath)
    guard target.directory.hasPrefix("/"),!target.directory.contains("\0"),target.directory.utf8.count<=8_192,
      !target.projectID.isEmpty,target.sessionID.hasPrefix("ses") else{throw RemoteError.invalidResponse}
    let name=String(relativePath.split(separator:"/").last!)
    guard name.utf8.count<=200,!name.unicodeScalars.contains(where:{$0.value<32 || $0.value==127}) else{throw RemoteError.incompatible}
    if let message=source.messageID{
      guard !message.isEmpty,message.utf8.count<=2_048,let index=source.fileIndex else{throw RemoteError.invalidResponse}
      switch source.kind{
      case .tool:guard let content=source.contentIndex,(0..<4_096).contains(content),(0..<128).contains(index) else{throw RemoteError.invalidResponse}
      case .snapshot:guard source.contentIndex==nil,(0..<1_000).contains(index) else{throw RemoteError.invalidResponse}
      case .selectedProjectFile:throw RemoteError.invalidResponse
      }
    }else{guard source.kind == .selectedProjectFile,source.contentIndex==nil,source.fileIndex==nil else{throw RemoteError.invalidResponse}}
    self.relativePath=relativePath;self.target=target;self.source=source;id=Self.identity(target:target,relativePath:relativePath)
  }
  public init(toolURI:String,target:OpenCodeTarget,source:OpenCodeResultSource=OpenCodeResultSource())throws{
    guard toolURI.utf8.count<=16_384,let uri=URLComponents(string:toolURI),uri.scheme=="file",
      uri.user==nil,uri.password==nil,uri.port==nil,uri.query==nil,uri.fragment==nil,
      uri.host==nil || uri.host=="" || uri.host?.lowercased()=="localhost",
      let path=uri.percentEncodedPath.removingPercentEncoding,path.hasPrefix("/"),!path.contains("\0") else{throw RemoteError.invalidResponse}
    var root=target.directory
    while root.count>1,root.hasSuffix("/"){root.removeLast()}
    let prefix=Array((root=="/" ? "/":root+"/").utf8),bytes=Array(path.utf8)
    guard bytes.starts(with:prefix) else{throw RemoteError.forbidden}
    try self.init(relativePath:String(decoding:bytes.dropFirst(prefix.count),as:UTF8.self),target:target,source:source)
  }
  private enum CodingKeys:String,CodingKey{case target,relativePath,source}
  public init(from decoder:any Decoder)throws{
    let c=try decoder.container(keyedBy:CodingKeys.self)
    try self.init(relativePath:c.decode(String.self,forKey:.relativePath),target:c.decode(OpenCodeTarget.self,forKey:.target),source:c.decode(OpenCodeResultSource.self,forKey:.source))
  }
  static func validatePath(_ path:String)throws{
    guard !path.isEmpty,path.utf8.count<=8_192,!path.hasPrefix("/"),!path.contains("\\"),
      !path.contains("\0"),!path.unicodeScalars.contains(where:{$0.value<32 || $0.value==127}),
      path.split(separator:"/",omittingEmptySubsequences:false).allSatisfy({!$0.isEmpty && $0 != "." && $0 != ".."}) else{throw RemoteError.invalidResponse}
  }
  public static func ==(a:Self,b:Self)->Bool{a.id==b.id && a.source==b.source}
  public func hash(into hasher:inout Hasher){hasher.combine(id);hasher.combine(source.kind.rawValue);hasher.combine(source.messageID.map(OpenCodeIdentity.key));hasher.combine(source.contentIndex);hasher.combine(source.fileIndex)}
}
public struct OpenCodeResultCatalog:Sendable {
  public let files:[OpenCodeResultFile]
  public let unsupportedReferences:Int
  public init(messages:[OpenCodeMessage],target:OpenCodeTarget){
    var files:[OpenCodeResultFile]=[],seen=Set<String>(),unsupported=0
    for message in messages where message.type=="assistant"{
      for (index,content) in message.content.enumerated(){
        unsupported+=content.unsupportedToolFiles
        for (fileIndex,ref) in content.toolFiles.enumerated(){
          guard content.toolState=="completed",let file=try? OpenCodeResultFile(toolURI:ref.uri,target:target,
            source:OpenCodeResultSource(messageID:message.id,contentIndex:index,fileIndex:fileIndex)) else{unsupported+=1;continue}
          if seen.insert(file.id).inserted{files.append(file)}
        }
      }
      unsupported+=message.unsupportedSnapshotFiles
      for (index,path) in message.snapshotFiles.enumerated(){
        guard let file=try? OpenCodeResultFile(relativePath:path,target:target,
          source:OpenCodeResultSource(messageID:message.id,fileIndex:index,kind:.snapshot)) else{unsupported+=1;continue}
        if seen.insert(file.id).inserted{files.append(file)}
      }
    }
    self.files=files;unsupportedReferences=unsupported
  }
}
public struct OpenCodeProjectFile:Decodable,Sendable,Identifiable {
  public let path:String
  public let type:String
  public var id:Data{OpenCodeIdentity.key(path)}
}
public enum OpenCodeFilePreviewKind:String,Sendable,Codable {case text,image,pdf,shareOnly}
public struct OpenCodeResultInfo:Sendable,Equatable {
  public let file:OpenCodeResultFile
  public let bytes:Int
  public let mime:String
  public let entityTag:String
  public let previewKind:OpenCodeFilePreviewKind
  public func validate()throws{
    guard (1...20*1_048_576).contains(bytes),entityTag.utf8.count<=256,
      entityTag.range(of:#"^(W/)?"[!#-~]{1,128}"$"#,options:.regularExpression) != nil,
      try Self.kind(name:file.name,mime:mime)==previewKind else{throw RemoteError.invalidResponse}
  }
  fileprivate static func kind(name:String,mime:String)throws->OpenCodeFilePreviewKind{
    let ext=(name as NSString).pathExtension.lowercased()
    switch mime{
    case "text/plain","text/markdown","text/csv","application/json":
      guard ["txt","md","csv","json","log"].contains(ext) else{throw RemoteError.incompatible};return .text
    case "image/png":guard ext=="png" else{throw RemoteError.incompatible};return .image
    case "image/jpeg":guard ["jpg","jpeg"].contains(ext) else{throw RemoteError.incompatible};return .image
    case "application/pdf":guard ext=="pdf" else{throw RemoteError.incompatible};return .pdf
    case "application/rtf","text/rtf":guard ext=="rtf" else{throw RemoteError.incompatible};return .shareOnly
    default:throw RemoteError.incompatible
    }
  }

}
public struct OpenCodeResultDownload:Sendable,CustomStringConvertible,CustomDebugStringConvertible {
  public let info:OpenCodeResultInfo
  public let data:Data
  public let sha256:String
  public var description:String{"OpenCodeResultDownload(<redacted>)"}
  public var debugDescription:String{description}
}
public protocol OpenCodeResultServing:AnyObject,Sendable {
  func projectFiles(target:OpenCodeTarget,directory:String?) async throws->[OpenCodeProjectFile]
  func probeResult(_ file:OpenCodeResultFile) async throws->OpenCodeResultInfo
  func downloadResult(_ info:OpenCodeResultInfo) async throws->OpenCodeResultDownload
}
extension OpenCodeClient:OpenCodeResultServing {
  public func projectFiles(target:OpenCodeTarget,directory:String?) async throws->[OpenCodeProjectFile]{
    if let directory{try OpenCodeResultFile.validatePath(directory)}
    _=try await verifyTarget(target)
    var query=try locationQuery(OpenCodeLocation(directory:target.directory))
    if let directory{query.append(URLQueryItem(name:"path",value:directory))}
    struct Response:Decodable,Sendable{let location:OpenCodeLocation;let data:[OpenCodeProjectFile]}
    let response=try await decode(Response.self,segments:["api","fs","list"],query:query)
    guard response.location==OpenCodeLocation(directory:target.directory),response.data.count<=10_000,
      Set(response.data.map(\.id)).count==response.data.count else{throw RemoteError.invalidResponse}
    for entry in response.data{
      guard ["file","directory"].contains(entry.type),entry.type=="directory" || !entry.path.hasSuffix("/") else{throw RemoteError.invalidResponse}
      let path=entry.type=="directory" && entry.path.hasSuffix("/") ? String(entry.path.dropLast()):entry.path
      try OpenCodeResultFile.validatePath(path)
      let parent=path.split(separator:"/").dropLast().joined(separator:"/")
      guard OpenCodeIdentity.matches(parent,directory ?? "") else{throw RemoteError.invalidResponse}
    }
    return response.data
  }
  public func probeResult(_ file:OpenCodeResultFile) async throws->OpenCodeResultInfo{
    _=try await verifyTarget(file.target)
    var request=try resultRequest(file);request.setValue("bytes=0-0",forHTTPHeaderField:"Range")
    let response=try await transport.binary(for:request,maximumBytes:1)
    if response.status==304{throw RemoteError.invalidResponse}
    if response.status==416{throw response.contentRange=="bytes */0" ? RemoteError.incompatible:RemoteError.conflict}
    try checkStatus(response.status)
    guard response.status==206,response.data.count==1,response.length==1,
      let range=response.contentRange,range.hasPrefix("bytes 0-0/"),let count=Int(range.dropFirst(10)),count>0 else{throw RemoteError.invalidResponse}
    guard count<=20*1_048_576 else{throw RemoteError.oversized}
    guard let mime=response.mime?.lowercased(),let tag=response.entityTag,tag.utf8.count<=256,
      tag.range(of:#"^(W/)?"[!#-~]{1,128}"$"#,options:.regularExpression) != nil else{throw RemoteError.invalidResponse}
    return OpenCodeResultInfo(file:file,bytes:count,mime:mime,entityTag:tag,previewKind:try OpenCodeResultInfo.kind(name:file.name,mime:mime))
  }
  public func downloadResult(_ info:OpenCodeResultInfo) async throws->OpenCodeResultDownload{
    guard try await probeResult(info.file)==info else{throw RemoteError.conflict}
    var request=try resultRequest(info.file)
    request.setValue("bytes=0-\(info.bytes-1)",forHTTPHeaderField:"Range");request.setValue(info.entityTag,forHTTPHeaderField:"If-Range")
    let response=try await transport.binary(for:request,maximumBytes:info.bytes)
    if [200,304,416].contains(response.status){throw RemoteError.conflict}
    try checkStatus(response.status)
    guard response.status==206,response.entityTag==info.entityTag else{throw RemoteError.conflict}
    guard response.mime?.lowercased()==info.mime,response.length==info.bytes,response.data.count==info.bytes,
      response.contentRange=="bytes 0-\(info.bytes-1)/\(info.bytes)" else{throw RemoteError.invalidResponse}
    guard try await probeResult(info.file)==info else{throw RemoteError.conflict}
    return OpenCodeResultDownload(info:info,data:response.data,sha256:SHA256.hash(data:response.data).map{String(format:"%02x",$0)}.joined())
  }
  private func resultRequest(_ file:OpenCodeResultFile)throws->URLRequest{
    try validateTarget(file.target)
    return try makeRequest(segments:["api","fs","read",file.relativePath],query:locationQuery(OpenCodeLocation(directory:file.target.directory)))
  }
}
