import Foundation
import CryptoKit

/// Durable identity is separate from inline bytes, which stay in protected file storage.
public struct OpenCodePromptFile:Codable,Sendable,Equatable,CustomStringConvertible,CustomDebugStringConvertible {
  public enum Placement:String,Codable,Sendable{case inline,staged}
  public let id:UUID
  public let target:OpenCodeTarget
  public let name:String
  public let mime:String
  public let bytes:Int
  public let sha256:String
  public let placement:Placement
  private let serverTmp:String?
  private var content:Data?
  private enum CodingKeys:String,CodingKey{case id,target,name,mime,bytes,sha256,placement,serverTmp}
  init(id:UUID=UUID(),target:OpenCodeTarget,name:String,mime:String,content:Data,placement:Placement,serverTmp:String?=nil)throws{
    self.id=id;self.target=target;self.name=name;self.mime=mime;self.bytes=content.count
    sha256=SHA256.hash(data:content).map{String(format:"%02x",$0)}.joined()
    self.placement=placement;self.serverTmp=serverTmp;self.content=placement == .inline ? content : nil
    try validate()
  }
  public init(from decoder:any Decoder)throws{
    let c=try decoder.container(keyedBy:CodingKeys.self)
    id=try c.decode(UUID.self,forKey:.id);target=try c.decode(OpenCodeTarget.self,forKey:.target)
    name=try c.decode(String.self,forKey:.name);mime=try c.decode(String.self,forKey:.mime);bytes=try c.decode(Int.self,forKey:.bytes)
    sha256=try c.decode(String.self,forKey:.sha256);placement=try c.decode(Placement.self,forKey:.placement)
    serverTmp=try c.decodeIfPresent(String.self,forKey:.serverTmp);content=nil;try validate()
  }
  public var stagedPath:String?{
    guard placement == .staged,let serverTmp else{return nil}
    return (serverTmp=="/" ? "" : serverTmp)+"/uploads/"+id.uuidString.lowercased()+"/"+name
  }
  public func inlineURI()throws->String{
    guard placement == .inline,let content else{throw RemoteError.unavailable}
    return "data:"+mime+";base64,"+content.base64EncodedString()
  }
  /// Restore bytes only from the protected local file after verifying its saved identity.
  public func withBytes(_ data:Data)throws->Self{
    guard data.count==bytes,SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined()==sha256 else{throw RemoteError.conflict}
    var copy=self;if placement == .inline{copy.content=data};return copy
  }
  func validate()throws{
    try AttachmentValidation.metadata(name:name,mime:mime,bytes:bytes,sha256:sha256)
    guard ["image/png","application/pdf"].contains(mime),!target.projectID.isEmpty,target.sessionID.hasPrefix("ses") else{throw RemoteError.invalidResponse}
    try OpenCodeLocation.validate(target.directory)
    if placement == .staged{guard let serverTmp,try Self.root(serverTmp)==serverTmp else{throw RemoteError.invalidResponse}}
    else{guard serverTmp==nil else{throw RemoteError.invalidResponse}}
  }
  static func root(_ path:String)throws->String{
    try OpenCodeLocation.validate(path)
    guard path.utf8.count<=8_000,!path.hasPrefix("//"),!path.split(separator:"/").contains(where:{$0=="." || $0==".."}) else{throw RemoteError.invalidResponse}
    var value=path;while value.count>1,value.hasSuffix("/"){value.removeLast()};return value
  }
  static func safeName(_ name:String,mime:String)throws->String{
    guard name.utf8.count<=4_096 else{throw RemoteError.oversized}
    let base=String(name.replacingOccurrences(of:"\\",with:"/").split(separator:"/").last ?? "attachment")
    var clean=String(String.UnicodeScalarView(base.unicodeScalars.map{$0.value<32 || $0.value==127 || $0.value==96 ? UnicodeScalar(95)! : $0}))
      .trimmingCharacters(in:.whitespacesAndNewlines)
    if clean.isEmpty || clean=="." || clean==".."{clean="attachment"}
    let suffix=mime=="image/png" ? ".png" : ".pdf"
    if !clean.lowercased().hasSuffix(suffix){clean+=suffix}
    while clean.utf8.count>200{let index=clean.index(clean.endIndex,offsetBy:-suffix.count);let prior=clean.index(before:index);clean.removeSubrange(prior..<index)}
    return clean
  }
  static func validateContent(_ data:Data,mime:String)throws{
    guard !data.isEmpty else{throw RemoteError.invalidResponse}
    guard data.count<=20*1_048_576 else{throw RemoteError.oversized}
    switch mime{
    case "application/pdf":
      guard String(decoding:data.prefix(16),as:UTF8.self).range(of:#"^%PDF-[12]\.[0-9]"#,options:.regularExpression) != nil,
        String(decoding:data.suffix(1_024),as:UTF8.self).range(of:#"%%EOF\s*$"#,options:.regularExpression) != nil else{throw RemoteError.invalidResponse}
    case "image/png":
      guard data.count>=45,data.starts(with:[137,80,78,71,13,10,26,10]),Array(data[12..<16])==Array("IHDR".utf8),
        Array(data.suffix(8).prefix(4))==Array("IEND".utf8) else{throw RemoteError.invalidResponse}
    default:throw RemoteError.incompatible
    }
  }
  /// OpenCode2.0.29's Base64 schema uses a repeated-group regex. Its pinned
  /// Bun1.4.2 rejects large valid strings; larger PDFs use the native file path.
  var fitsQualifiedInlineLimits:Bool{
    if mime=="application/pdf"{return bytes<=5*1_048_576}
    guard mime=="image/png",let content,content.count>=24 else{return mime != "image/png"}
    func integer(_ start:Int)->UInt32{content[start..<start+4].reduce(0){($0<<8)|UInt32($1)}}
    let width=integer(16),height=integer(20)
    return width>0 && height>0 && width<=2_000 && height<=2_000 && ((bytes+2)/3)*4<=5*1_048_576
  }
  func usesStagingRoot(_ root:String)throws->Bool{
    guard placement == .staged else{return true}
    return OpenCodeIdentity.matches(serverTmp,try Self.root(root))
  }
  public static func ==(a:Self,b:Self)->Bool{
    a.id==b.id && a.target==b.target && OpenCodeIdentity.matches(a.name,b.name) && a.mime==b.mime && a.bytes==b.bytes &&
      a.sha256==b.sha256 && a.placement==b.placement && OpenCodeIdentity.matches(a.serverTmp,b.serverTmp)
  }
  public var description:String{"OpenCodePromptFile(<redacted>)"}
  public var debugDescription:String{description}
}
extension OpenCodeClient {
  func effectiveAttachmentModel(session:OpenCodeSession,target:OpenCodeTarget) async throws -> OpenCodeModel{
    let location=OpenCodeLocation(directory:target.directory)
    var ref=session.model
    if ref==nil,let agent=session.agent{ref=try await agents(location:location).first{$0.id==agent}?.model}
    if ref==nil,let model=try await defaultModel(location:location){ref=try OpenCodeModelRef(providerID:model.providerID,id:model.id)}
    guard let ref,let model=try await models(location:location).first(where:{$0.accepts(ref)}) else{throw RemoteError.unavailable}
    return model
  }
  public func attachmentModel(target:OpenCodeTarget) async throws -> OpenCodeModel{
    let actual=try await verifyTarget(target);return try await effectiveAttachmentModel(session:actual,target:target)
  }
  public func prepareAttachment(bytes:Data,name:String,mime:String,target:OpenCodeTarget,model:OpenCodeModel) async throws -> OpenCodePromptFile{
    try OpenCodePromptFile.validateContent(bytes,mime:mime)
    let clean=try OpenCodePromptFile.safeName(name,mime:mime)
    let actual=try await verifyTarget(target)
    if let ref=actual.model{guard OpenCodeIdentity.matches(ref.id,model.id),OpenCodeIdentity.matches(ref.providerID,model.providerID) else{throw RemoteError.conflict}}
    let current=try await effectiveAttachmentModel(session:actual,target:target)
    guard current.selectionKey==model.selectionKey else{throw RemoteError.conflict}
    let modality=mime=="image/png" ? "image" : "pdf"
    let candidate=try OpenCodePromptFile(target:target,name:clean,mime:mime,content:bytes,placement:.inline)
    if current.capabilities.input.contains(modality),candidate.fitsQualifiedInlineLimits{return candidate}
    guard current.capabilities.tools else{throw RemoteError.incompatible}
    let root=try OpenCodePromptFile.root(try await info().paths.tmp)
    let staged=try OpenCodePromptFile(target:target,name:clean,mime:mime,content:bytes,placement:.staged,serverTmp:root)
    let path=staged.stagedPath!
    var query=try locationQuery(OpenCodeLocation(directory:target.directory));query.append(URLQueryItem(name:"path",value:path))
    let response:Data
    do{response=try await data(segments:["api","experimental","fs","write"],query:query,method:"POST",body:bytes,contentType:"application/octet-stream")}
    catch{if [.unauthorized,.forbidden,.incompatible].contains(error as? RemoteError){throw error};throw RemoteError.outcomeUnknown}
    struct Response:Decodable{let location:OpenCodeLocation;let data:Path}
    struct Path:Decodable{let path:String}
    guard let result=try? JSONDecoder().decode(Response.self,from:response),result.location==OpenCodeLocation(directory:target.directory),
      OpenCodeIdentity.matches(result.data.path,path) else{throw RemoteError.outcomeUnknown}
    return staged
  }
}
