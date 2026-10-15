#if DEBUG
import SwiftUI
import UIKit
import OpenWorkRemoteCore

/// Exercises the shared production views through the typed native HTTP client.
/// Synthetic origin/credential; every response is in-process, no real network.
private actor NativeAppUITestTransport:HTTPTransport {
  var admitted:[String:Any]?
  var title="Native chat"
  var extra:[String:[String:Any]]=[:]
  var deleted=Set<String>()
  let slow:Bool
  init(slow:Bool){self.slow=slow}
  private var record:[String:Any]{["id":"ses_owned","projectID":"project","title":title,"location":["directory":"/project"],"time":["created":1,"updated":2],"model":["providerID":"Synthetic provider","id":"native-model"],"agent":"build","permissions":[]]}
  private var form:[String:Any]{["id":"frm_owned","sessionID":"ses_owned","title":"Which option do you prefer?","fields":[["key":"answer","type":"string","required":true]],"state":["status":"pending"]]}
  private var model:[String:Any]{["providerID":"Synthetic provider","id":"native-model","modelID":"native-model","name":"Native model","enabled":true,"status":"active","variants":[],"capabilities":["tools":true,"input":["text","image","pdf"],"output":["text"]]]}
  func data(for request:URLRequest) async throws -> (Data,Int){
    let path=request.url!.path,value:Any
    switch path{
    case "/api/info":value=["version":"2.0.29","urls":[],"paths":["tmp":"/tmp/native"]]
    case "/api/project":value=[["id":"project","name":"Native project","canonical":"/project","sandboxes":[],"time":["created":1,"updated":2,"active":2]]]
    case "/api/location":value=["directory":"/project","project":["id":"project","directory":"/project","canonical":"/project"]]
    case "/api/session":
      if request.httpMethod=="POST"{
        let body=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
        let id=body["id"] as! String
        var row=record;row["id"]=id;row["title"]="New chat";row["metadata"]=body["metadata"];extra[id]=row
        value=["data":row]
      }else{
        let query=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems ?? []
        if query.contains(where:{$0.name=="parentID"}){value=["data":[],"cursor":[:]]}
        else{
          let search=query.first(where:{$0.name=="search"})?.value
          let rows=([record]+Array(extra.values)).filter{row in !deleted.contains(row["id"] as! String) && (search.map{(row["title"] as? String ?? "").localizedCaseInsensitiveContains($0)} ?? true)}
          value=["data":rows,"cursor":[:]]
        }
      }
    case "/api/session/ses_owned":
      if request.httpMethod=="PATCH"{title=(try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:String])["title"]!;return(Data(),204)}
      if request.httpMethod=="DELETE"{deleted.insert("ses_owned");return(Data(),204)}
      if deleted.contains("ses_owned"){return(Data(),404)}
      value=["data":record]
    case "/api/session/ses_owned/fork":
      var row=record;row["id"]="ses_fork";row["title"]=title+" (fork #1)";extra["ses_fork"]=row;value=["data":row]
    case "/api/session/ses_owned/message":
      value=["data":[["id":"msg_owned","type":"user","text":"Native message","time":["created":1]],
        ["id":"msg_result","type":"assistant","time":["created":2],"content":[["type":"text","text":"Your result is ready."],["type":"tool","name":"generate","state":["status":"completed","content":[["type":"file","uri":"file:///project/result.txt","mime":"text/plain"]]]]]]],"cursor":[:]]
    case "/api/fs/list":value=["location":["directory":"/project"],"data":[["path":"project-only.txt","type":"file"]]]
    case "/api/session/ses_owned/prompt":
      let body=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
      let files=(body["files"] as? [[String:Any]] ?? []).map{file -> [String:Any] in
        let uri=file["uri"] as! String,parts=uri.split(separator:",",maxSplits:1)
        return ["name":file["name"]!,"mime":String(parts[0].dropFirst(5).split(separator:";")[0]),"data":String(parts[1]),"source":["type":"inline"]]
      }
      admitted=["id":body["id"]!,"sessionID":"ses_owned","type":"user","payload":["text":body["text"]!,"files":files]]
      value=["data":admitted!]
    case "/api/session/ses_owned/inbox":value=["data":admitted.map{[$0]} ?? []]
    case "/api/session/active":value=["data":[:]]
    case "/api/session/ses_owned/permission":value=["data":[["id":"per_owned","sessionID":"ses_owned","action":"read","resources":["notes.txt"]]]]
    case "/api/session/ses_owned/form":value=["data":[form]]
    case "/api/session/ses_owned/form/frm_owned":value=["data":form]
    case "/api/model":
      if slow{try await Task.sleep(for:.seconds(30))}
      value=["location":["directory":"/project"],"data":[model]]
    case "/api/model/default":value=["location":["directory":"/project"],"data":model]
    case "/api/agent":value=["location":["directory":"/project"],"data":[["id":"build","name":"Build","mode":"primary","hidden":false,"permissions":[]]]]
    case "/api/permission/saved":value=["data":[]]
    default:
      let segments=path.split(separator:"/").map(String.init)
      if segments.count>=3,segments[0]=="api",segments[1]=="session"{
        let id=segments[2]
        if segments.count==3{
          if request.httpMethod=="DELETE"{deleted.insert(id);return(Data(),204)}
          if deleted.contains(id){return(Data(),404)}
          if request.httpMethod=="PATCH",var row=extra[id]{row["title"]=(try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:String])["title"];extra[id]=row;return(Data(),204)}
          guard let row=extra[id] else{return(Data(),404)};value=["data":row]
        }else if segments[3]=="message"{value=["data":[],"cursor":[:]]}
        else if ["inbox","permission","form"].contains(segments[3]){value=["data":[]]}
        else{throw RemoteError.invalidResponse}
      }else{throw RemoteError.invalidResponse}
    }
    return(try JSONSerialization.data(withJSONObject:value),200)
  }
  func binary(for request:URLRequest,maximumBytes:Int) async throws -> BinaryHTTPResponse{
    let text=request.url!.path.hasSuffix("project-only.txt") ? "Selected project file\n":"Synthetic generated result\n"
    let bytes=Data(text.utf8),probe=request.value(forHTTPHeaderField:"Range")=="bytes=0-0"
    return BinaryHTTPResponse(data:probe ? bytes.prefix(1):bytes,status:206,mime:"text/plain",
      contentRange:probe ? "bytes 0-0/\(bytes.count)":"bytes 0-\(bytes.count-1)/\(bytes.count)",entityTag:"W/\"fixture\"",length:probe ? 1:bytes.count)
  }
  func events(for request:URLRequest) async throws -> AsyncThrowingStream<SSEFrame,any Error>{AsyncThrowingStream{_ in}}
}
struct NativeAppUITestFixture:View {
  @State private var model:AppModel
  init(){
    if ProcessInfo.processInfo.arguments.contains("-native-fixture-no-animations"){UIView.setAnimationsEnabled(false)}
    let directory=FileManager.default.temporaryDirectory.appending(path:"native-shell-ui-"+UUID().uuidString)
    let saved=StoredOpenCodeConnection(connection:try! OpenCodeConnection(origin:URL(string:"https://synthetic.example")!,displayName:"Synthetic computer"),token:"synthetic-token")
    let native=try! NativeAppCoordinator(directory:directory,connectionPersistence:OpenCodePersistence(load:{saved},save:{_ in},remove:{}),transport:NativeAppUITestTransport(slow:ProcessInfo.processInfo.arguments.contains("-slow-native-app-settings")))
    _model=State(initialValue:AppModel(native:native,legacyDraftStore:try! DraftStore(directory:directory),pairingPersistence:PairingPersistence(load:{nil},save:{_ in},remove:{})))
  }
  var body:some View{NavigationStack{ChatView()}.environment(model).tint(Theme.accent).transaction{transaction in
    if ProcessInfo.processInfo.arguments.contains("-native-fixture-no-animations"){transaction.disablesAnimations=true;transaction.animation=nil}
  }.task{await model.start()}}
}
#endif
