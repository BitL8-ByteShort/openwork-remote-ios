import Foundation
import CryptoKit

/// The native server materializes files before admission. Keep their identity,
/// not multi-megabyte base64 strings, in ordinary conversation state.
public struct OpenCodeMaterializedFile:Decodable,Sendable,Equatable {
  public let name:String?
  public let mime:String?
  public let sourceType:String?
  public let sourceURI:String?
  public let bytes:Int?
  public let sha256:String?
  private enum CodingKeys:String,CodingKey{case data,name,mime,source}
  private struct Source:Decodable{let type:String?;let uri:String?}
  public init(from decoder:any Decoder)throws{
    let c=try decoder.container(keyedBy:CodingKeys.self)
    let name=try c.decodeIfPresent(String.self,forKey:.name),mime=try c.decodeIfPresent(String.self,forKey:.mime)
    let source=try c.decodeIfPresent(Source.self,forKey:.source)
    self.name=name.map{$0.utf8.count<=2_048 ? $0 : "Attachment"};self.mime=(mime?.utf8.count ?? 0)<=256 ? mime : nil
    sourceType=(source?.type?.utf8.count ?? 0)<=32 ? source?.type : nil;sourceURI=(source?.uri?.utf8.count ?? 0)<=16_384 ? source?.uri : nil
    let encoded=try c.decodeIfPresent(String.self,forKey:.data)
    if let encoded,encoded.utf8.count<=((20*1_048_576+2)/3)*4,let data=Data(base64Encoded:encoded),data.count<=20*1_048_576,
       data.base64EncodedString()==encoded{
      bytes=data.count;sha256=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
    }else{bytes=nil;sha256=nil}
  }
  func matches(_ file:OpenCodePromptFile)->Bool{
    file.placement == .inline && sourceType=="inline" && sourceURI==nil &&
      OpenCodeIdentity.matches(name,file.name) && mime==file.mime && bytes==file.bytes && sha256==file.sha256
  }
  public static func ==(a:Self,b:Self)->Bool{
    OpenCodeIdentity.matches(a.name,b.name) && OpenCodeIdentity.matches(a.mime,b.mime) &&
      OpenCodeIdentity.matches(a.sourceType,b.sourceType) && OpenCodeIdentity.matches(a.sourceURI,b.sourceURI) && a.bytes==b.bytes && a.sha256==b.sha256
  }
}
struct OpenCodeSkillIdentity:Decodable,Sendable{
  let id:String?
  private enum CodingKeys:String,CodingKey{case id}
  init(from decoder:any Decoder)throws{
    let value=try decoder.container(keyedBy:CodingKeys.self).decodeIfPresent(String.self,forKey:.id)
    id=(value?.utf8.count ?? 0)<=2_048 ? value : nil
  }
}
