import Foundation

/// Use official display metadata only when it accounts for the complete text.
/// Otherwise preserve every byte of the native message in the conversation.
struct OpenCodeMessagePresentation:Decodable,Sendable,Equatable {
  struct Reference:Decodable,Sendable,Equatable {
    let name:String;let mime:String;let path:String
    static func ==(a:Self,b:Self)->Bool{OpenCodeIdentity.matches(a.name,b.name) && OpenCodeIdentity.matches(a.mime,b.mime) && OpenCodeIdentity.matches(a.path,b.path)}
  }
  let original:String
  let attachments:[Reference]
  let commentCount:Int
  private enum CodingKeys:String,CodingKey{case displayText,attachments,comments}
  private struct Item:Decodable{}
  init(from decoder:any Decoder)throws{
    let c=try decoder.container(keyedBy:CodingKeys.self)
    original=try c.decode(String.self,forKey:.displayText)
    attachments=try c.decode([Reference].self,forKey:.attachments)
    commentCount=try c.decode([Item].self,forKey:.comments).count
    guard original.utf8.count<=32_768,attachments.count<=200,commentCount<=200,
      attachments.allSatisfy({$0.name.utf8.count<=2_048 && $0.mime.utf8.count<=256 && $0.path.utf8.count<=16_384}) else{throw RemoteError.oversized}
  }
  func displayText(ifMatching text:String)->String?{
    guard commentCount==0 else{return nil}
    let initial=original.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? [] : [original]
    let expanded=(initial+attachments.map{"Attached file: `"+$0.path+"`"}).joined(separator:"\n")
    return OpenCodeIdentity.matches(expanded,text) ? original : nil
  }
  var storedBytes:Int{original.utf8.count+attachments.reduce(0){$0+$1.name.utf8.count+$1.mime.utf8.count+$1.path.utf8.count}}
  static func ==(a:Self,b:Self)->Bool{OpenCodeIdentity.matches(a.original,b.original) && a.attachments==b.attachments && a.commentCount==b.commentCount}
}
