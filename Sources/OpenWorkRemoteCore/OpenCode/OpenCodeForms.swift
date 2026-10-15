import Foundation
import CryptoKit

public enum OpenCodeFormValue:Codable,Sendable,Equatable {
  case string(String),number(Double),bool(Bool),strings([String])
  public init(from decoder:any Decoder)throws{
    let c=try decoder.singleValueContainer()
    if let x=try? c.decode(Bool.self){self = .bool(x)}
    else if let x=try? c.decode(String.self){self = .string(x)}
    else if let x=try? c.decode([String].self){self = .strings(x)}
    else{let x=try c.decode(Double.self);guard x.isFinite else{throw RemoteError.invalidResponse};self = .number(x)}
  }
  public func encode(to encoder:any Encoder)throws{
    var c=encoder.singleValueContainer()
    switch self{case .string(let x):try c.encode(x);case .number(let x):try c.encode(x);case .bool(let x):try c.encode(x);case .strings(let x):try c.encode(x)}
  }
  public static func ==(a:Self,b:Self)->Bool{
    switch(a,b){
    case(.string(let x),.string(let y)):OpenCodeIdentity.matches(x,y)
    case(.number(let x),.number(let y)):x==y
    case(.bool(let x),.bool(let y)):x==y
    case(.strings(let x),.strings(let y)):OpenCodeIdentity.matches(x,y)
    default:false
    }
  }
}
public struct OpenCodeFormField:Codable,Sendable {
  public struct Option:Codable,Sendable{public let value:String;public let label:String;public let description:String?}
  public struct Condition:Codable,Sendable{public let key:String;public let op:String;public let value:OpenCodeFormValue}
  public let key:String
  public let type:String
  public let title:String?
  public let description:String?
  public let required:Bool?
  public let hidden:Bool?
  public let when:[Condition]?
  public let format:String?
  public let minLength:Int?
  public let maxLength:Int?
  public let pattern:String?
  public let placeholder:String?
  public let defaultValue:OpenCodeFormValue?
  public let options:[Option]?
  public let custom:Bool?
  public let minimum:Double?
  public let maximum:Double?
  public let minItems:Int?
  public let maxItems:Int?
  public let url:String?
  private enum CodingKeys:String,CodingKey{
    case key,type,title,description,required,hidden,when,format,minLength,maxLength,pattern,placeholder,options,custom,minimum,maximum,minItems,maxItems,url
    case defaultValue="default"
  }
  public var externalURL:URL?{
    guard type=="external",let url,url.utf8.count<=4_096,let parts=URLComponents(string:url),parts.scheme=="https",parts.host?.isEmpty==false,
      parts.user==nil,parts.password==nil,let result=parts.url else{return nil};return result
  }
  var supported:Bool{
    ["string","number","integer","boolean","multiselect"].contains(type) && hidden != true && pattern==nil &&
      (format==nil || ["email","uri","date","date-time"].contains(format!)) &&
      (type != "multiselect" || options != nil) &&
      (minLength.map{$0>=0} ?? true) && (maxLength.map{$0>=0} ?? true) &&
      (minItems.map{$0>=0} ?? true) && (maxItems.map{$0>=0} ?? true)
  }
}
public struct OpenCodeFormValidation:Error,Sendable,Equatable {
  public let field:String?
  public let message:String
  init(_ field:String?,_ message:String){self.field=field;self.message=message}
  init(_ message:String){self.field=nil;self.message=message}
}
public struct OpenCodeForm:Codable,Sendable,Identifiable {
  public struct State:Codable,Sendable{public let status:String;public let answer:[String:OpenCodeFormValue]?;public let message:String?}
  public let id:String
  public let sessionID:String
  public let title:String
  public let fields:[OpenCodeFormField]
  public let state:State?
  public var isPending:Bool{state==nil || state?.status=="pending"}
  public var definitionFingerprint:Data{
    struct Definition:Encodable{let title:String;let fields:[OpenCodeFormField]}
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
    return Data(SHA256.hash(data:(try? encoder.encode(Definition(title:title,fields:fields))) ?? Data()))
  }
  public var supported:Bool{
    guard !fields.isEmpty,fields.count<=200,Set(fields.map(\.key)).count==fields.count,fields.allSatisfy(\.supported) else{return false}
    var earlier:[String:OpenCodeFormField]=[:]
    for field in fields{
      for condition in field.when ?? []{
        guard let source=earlier[condition.key],["eq","neq"].contains(condition.op) else{return false}
        switch(source.type,condition.value){
        case("boolean",.bool), ("number",.number), ("integer",.number):break
        case("string",.string(let value)),("multiselect",.string(let value)):
          if source.custom != true,let options=source.options,!options.contains(where:{OpenCodeIdentity.matches($0.value,value)}){return false}
        default:return false
        }
      }
      earlier[field.key]=field
    }
    return true
  }
  public func activeFields(answer:[String:OpenCodeFormValue])->[OpenCodeFormField]{
    let active=activeAnswer(answer)
    return fields.filter{field in isActive(field,answer:active)}
  }
  /// Remove obsolete conditional answers in declaration order, including cascades.
  public func activeAnswer(_ answer:[String:OpenCodeFormValue])->[String:OpenCodeFormValue]{
    var result:[String:OpenCodeFormValue]=[:]
    for field in fields where isActive(field,answer:result){if let value=answer[field.key]{result[field.key]=value}}
    return result
  }
  private func isActive(_ field:OpenCodeFormField,answer:[String:OpenCodeFormValue])->Bool{
    (field.when ?? []).allSatisfy{condition in
      guard let value=answer[condition.key] else{return false}
      let equal:Bool
      if case .strings(let values)=value,case .string(let expected)=condition.value{equal=values.contains{OpenCodeIdentity.matches($0,expected)}}
      else{equal=value==condition.value}
      return condition.op=="eq" ? equal : condition.op=="neq" && !equal
    }
  }
  public func validate(answer:[String:OpenCodeFormValue])throws{
    guard supported else{throw OpenCodeFormValidation("Complete this form on your computer. It uses fields PocketWork cannot safely answer.")}
    guard answer.count<=200,answer.keys.allSatisfy({key in fields.contains{OpenCodeIdentity.matches($0.key,key)}}) else{throw OpenCodeFormValidation("The form contains an unknown answer.")}
    let active=activeAnswer(answer)
    for field in fields{
      guard let value=answer[field.key] else{
        if field.required==true,isActive(field,answer:active){throw OpenCodeFormValidation(field.key,"An answer is required.")};continue
      }
      guard isActive(field,answer:active) else{throw OpenCodeFormValidation(field.key,"This field is no longer active.")}
      switch(field.type,value){
      case("string",.string(let text)):
        let length=text.utf16.count
        guard text.utf8.count<=65_536,!(field.required==true && text.isEmpty),length >= (field.minLength ?? 0),length <= (field.maxLength ?? Int.max) else{throw OpenCodeFormValidation(field.key,"Check the answer’s length.")}
        if let options=field.options,field.custom != true,!options.contains(where:{OpenCodeIdentity.matches($0.value,text)}){throw OpenCodeFormValidation(field.key,"Choose one of the available options.")}
        if let format=field.format,!valid(text,format:format){throw OpenCodeFormValidation(field.key,"Enter a valid "+format+" value.")}
      case("number",.number(let number)),("integer",.number(let number)):
        guard number.isFinite,(field.type != "integer" || number.rounded(.towardZero)==number),number >= (field.minimum ?? -.infinity),number <= (field.maximum ?? .infinity) else{throw OpenCodeFormValidation(field.key,"Check the number and its allowed range.")}
      case("boolean",.bool):break
      case("multiselect",.strings(let values)):
        guard values.count<=2_000,values.count >= (field.minItems ?? (field.required==true ? 1 : 0)),values.count <= (field.maxItems ?? 2_000),!(field.required==true && values.isEmpty),values.allSatisfy({$0.utf8.count<=65_536}) else{throw OpenCodeFormValidation(field.key,"Check the number of selected options.")}
        if field.custom != true,values.contains(where:{value in !(field.options ?? []).contains{OpenCodeIdentity.matches($0.value,value)}}){throw OpenCodeFormValidation(field.key,"Choose available options.")}
      default:throw OpenCodeFormValidation(field.key,"The answer has the wrong type.")
      }
    }
  }
  private func valid(_ text:String,format:String)->Bool{
    switch format{
    case "email":return text.range(of:#"^[^\s@]+@[^\s@]+\.[^\s@]+$"#,options:.regularExpression) != nil
    case "uri":return URLComponents(string:text)?.scheme?.isEmpty==false
    case "date":
      guard text.range(of:#"^\d{4}-\d{2}-\d{2}$"#,options:.regularExpression) != nil else{return false}
      let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.timeZone=TimeZone(secondsFromGMT:0);formatter.dateFormat="yyyy-MM-dd";formatter.isLenient=false
      return formatter.date(from:text).map{formatter.string(from:$0)==text} ?? false
    case "date-time":
      let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
      if f.date(from:text) != nil{return true};f.formatOptions=[.withInternetDateTime];return f.date(from:text) != nil
    default:return false
    }
  }
  func validateEnvelope(target:OpenCodeTarget)throws{
    guard id.hasPrefix("frm_"),id.utf8.count<=2_048,OpenCodeIdentity.matches(sessionID,target.sessionID),title.utf8.count<=65_536,
      !fields.isEmpty,fields.count<=200,Set(fields.map(\.key)).count==fields.count,
      fields.allSatisfy({!$0.key.isEmpty && $0.key.utf8.count<=1_024 && ($0.options?.count ?? 0)<=2_000 && ($0.when?.count ?? 0)<=200}) else{throw RemoteError.invalidResponse}
  }
}

public enum OpenCodeFormResolution:Sendable{case confirmed,alreadyResolved}
public struct OpenCodeFormNotSubmitted:Error,Sendable,Equatable{
  public let reason:RemoteError
  public init(reason:RemoteError){self.reason=reason}
}
public protocol OpenCodeFormServing:Sendable {
  func forms(target:OpenCodeTarget) async throws -> [OpenCodeForm]
  func form(target:OpenCodeTarget,id:String) async throws -> OpenCodeForm
  func replyForm(target:OpenCodeTarget,form:OpenCodeForm,answer:[String:OpenCodeFormValue]) async throws -> OpenCodeFormResolution
  func cancelForm(target:OpenCodeTarget,form:OpenCodeForm) async throws -> OpenCodeFormResolution
}
extension OpenCodeClient:OpenCodeFormServing {
  public func forms(target:OpenCodeTarget) async throws -> [OpenCodeForm]{
    try validateTarget(target)
    struct Response:Decodable,Sendable{let data:[OpenCodeForm]}
    let values=try await decode(Response.self,segments:["api","session",target.sessionID,"form"]).data
    guard values.count<=200,Set(values.map(\.id)).count==values.count else{throw RemoteError.invalidResponse}
    for value in values{try value.validateEnvelope(target:target)}
    return values.filter(\.isPending)
  }
  public func form(target:OpenCodeTarget,id:String) async throws -> OpenCodeForm{
    try validateTarget(target)
    guard id.hasPrefix("frm_"),id.utf8.count<=2_048 else{throw RemoteError.invalidResponse}
    struct Response:Decodable,Sendable{let data:OpenCodeForm}
    let value=try await decode(Response.self,segments:["api","session",target.sessionID,"form",id]).data
    try value.validateEnvelope(target:target)
    guard OpenCodeIdentity.matches(value.id,id),let state=value.state,["pending","answered","cancelled"].contains(state.status),
      state.status != "answered" || state.answer != nil else{throw RemoteError.invalidResponse}
    return value
  }
  public func replyForm(target:OpenCodeTarget,form:OpenCodeForm,answer:[String:OpenCodeFormValue]) async throws -> OpenCodeFormResolution{
    try await settleForm(target:target,reviewed:form,answer:answer)
  }
  public func cancelForm(target:OpenCodeTarget,form:OpenCodeForm) async throws -> OpenCodeFormResolution{
    try await settleForm(target:target,reviewed:form,answer:nil)
  }
  private func settleForm(target:OpenCodeTarget,reviewed:OpenCodeForm,answer:[String:OpenCodeFormValue]?) async throws -> OpenCodeFormResolution{
    let request:URLRequest
    do{
      try await verifyTarget(target)
      try reviewed.validateEnvelope(target:target)
      let current=try await form(target:target,id:reviewed.id)
      guard current.isPending else{return .alreadyResolved}
      guard current.definitionFingerprint==reviewed.definitionFingerprint else{throw RemoteError.conflict}
      var body:Data?
      if let answer{
        try current.validate(answer:answer)
        struct Body:Encodable{let answer:[String:OpenCodeFormValue]}
        body=try JSONEncoder().encode(Body(answer:answer))
        guard body!.count<=256*1_024 else{throw RemoteError.oversized}
      }
      try await requireQualifiedWrites()
      let segments=["api","session",target.sessionID,"form",reviewed.id]+(answer==nil ? [] : ["reply"])
      request=try makeRequest(segments:segments,method:answer==nil ? "DELETE" : "POST",body:body)
    }catch{
      throw OpenCodeFormNotSubmitted(reason:(error as? RemoteError) ?? (error is OpenCodeFormValidation ? .invalidResponse : .unavailable))
    }
    do{
      let (bytes,status)=try await transport.data(for:request)
      if [400,401,403,404,413,422].contains(status){
        do{try checkStatus(status)}catch{throw OpenCodeFormNotSubmitted(reason:(error as? RemoteError) ?? .invalidResponse)}
      }
      guard bytes.count<=8_388_608,status==204 else{throw RemoteError.outcomeUnknown}
    }catch let rejected as OpenCodeFormNotSubmitted{throw rejected}
    catch{
      // The write may have succeeded. Only native state can resolve it; never replay.
      return try await settledFormResult(target:target,id:reviewed.id,answer:answer)
    }
    return try await settledFormResult(target:target,id:reviewed.id,answer:answer)
  }
  private func settledFormResult(target:OpenCodeTarget,id:String,answer:[String:OpenCodeFormValue]?) async throws -> OpenCodeFormResolution{
    let actual:OpenCodeForm
    do{actual=try await form(target:target,id:id)}catch{throw RemoteError.outcomeUnknown}
    if actual.state?.status=="answered"{return actual.state?.answer==answer ? .confirmed : .alreadyResolved}
    if actual.state?.status=="cancelled"{return answer==nil ? .confirmed : .alreadyResolved}
    throw RemoteError.outcomeUnknown
  }
}
