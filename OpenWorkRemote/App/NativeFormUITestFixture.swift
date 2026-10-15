#if DEBUG
import SwiftUI
import OpenWorkRemoteCore

private actor NativeFormUITestService:OpenCodeFormServing {
  let external:Bool
  let uncertain:Bool
  let changed:Bool
  var attempted=false
  var status="pending"
  var answer:[String:OpenCodeFormValue]?
  init(){let args=ProcessInfo.processInfo.arguments;external=args.contains("-native-form-external");uncertain=args.contains("-native-form-uncertain");changed=args.contains("-native-form-changed")}
  func forms(target:OpenCodeTarget) async throws -> [OpenCodeForm]{status=="pending" ? [try await form(target:target,id:"frm_synthetic")] : []}
  func form(target:OpenCodeTarget,id:String) async throws -> OpenCodeForm{
    let fields:[String:Any]=["key":"approach","type":"string","title":attempted && changed ? "Updated question" : "Which approach should we use?","required":true,"options":[["value":"simple","label":"Simple and focused"],["value":"detailed","label":"More detail"]]]
    let number:[String:Any]=["key":"count","type":"integer","title":"How many examples?","required":true,"minimum":1,"maximum":3,"when":[["key":"approach","op":"eq","value":"detailed"]]]
    let link:[String:Any]=["key":"browser","type":"external","url":"https://synthetic.example/review","title":"Continue in browser"]
    var state:[String:Any]=["status":status];if let answer{state["answer"]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(answer))}
    return try JSONDecoder().decode(OpenCodeForm.self,from:JSONSerialization.data(withJSONObject:["id":id,"sessionID":target.sessionID,"title":"Choose an approach","fields":external ? [link] : [fields,number],"state":state]))
  }
  func replyForm(target:OpenCodeTarget,form:OpenCodeForm,answer:[String:OpenCodeFormValue]) async throws -> OpenCodeFormResolution{
    attempted=true;if changed{throw OpenCodeFormNotSubmitted(reason:.conflict)};if uncertain{throw RemoteError.outcomeUnknown}
    self.answer=answer;status="answered";return .confirmed
  }
  func cancelForm(target:OpenCodeTarget,form:OpenCodeForm) async throws -> OpenCodeFormResolution{status="cancelled";return .confirmed}
}
private struct NativeFormUIPresentation:Identifiable {
  let id=UUID()
  let context:NativeFormContext
}
struct NativeFormUITestFixture:View {
  @State private var store:NativeFormStore
  @State private var context:NativeFormContext?
  @State private var presentation:NativeFormUIPresentation?
  init(){_store=State(initialValue:NativeFormStore(persistence:try! NativeFormFile(directory:FileManager.default.temporaryDirectory.appending(path:"native-form-ui-"+UUID().uuidString))))}
  var body:some View{
    Button("Open question"){if let context{presentation=NativeFormUIPresentation(context:context)}}.accessibilityIdentifier("native-form-open")
      .task{
        if context==nil{
          try? await store.restore()
          let activated=store.activate(target:OpenCodeTarget(connectionID:ConnectionID(),projectID:"project",sessionID:"ses_synthetic",directory:"/synthetic"),client:NativeFormUITestService())
          context=activated;presentation=NativeFormUIPresentation(context:activated)
        }
      }.sheet(item:$presentation){request in NativeFormSheet(store:store,context:request.context,formID:"frm_synthetic")}
  }
}
#endif
