import Foundation
import Testing
@testable import OpenWorkRemoteCore

@Suite struct OpenCodeFormTests {
  func form(_ fields:String)->OpenCodeForm {
    try! JSONDecoder().decode(OpenCodeForm.self,from:Data((#"{"id":"frm_owned","sessionID":"ses_owned","title":"Choose the approach","fields":\#(fields)}"#).utf8))
  }
  @Test func nestedCreatedFormEventIdentifiesItsConversation() throws {
    let frame=SSEFrame(event:"message",id:nil,data:#"{"id":"evt_owned","type":"form.created","data":{"form":{"id":"frm_owned","sessionID":"ses_owned"}}}"#)
    let event=try OpenCodeEvent.decode(frame)
    #expect(event.affects(OpenCodeTarget(connectionID:ConnectionID(),projectID:"project",sessionID:"ses_owned",directory:"/project")))
  }
  @Test func choiceCustomAndUTF16StringLengthUseNativeSemantics() throws {
    let closed=form(#"[{"key":"choice","type":"string","required":true,"options":[{"value":"small","label":"Simple"}]}]"#)
    #expect(throws:OpenCodeFormValidation.self){try closed.validate(answer:["choice":.string("other")])}
    try closed.validate(answer:["choice":.string("small")])
    let custom=form(#"[{"key":"choice","type":"string","required":true,"custom":true,"maxLength":2,"options":[]}]"#)
    try custom.validate(answer:["choice":.string("🙂")])
    #expect(throws:OpenCodeFormValidation.self){try custom.validate(answer:["choice":.string("🙂x")])}
  }
  @Test func conditionsCascadeAndInactiveDraftValuesCannotBeSubmitted() throws {
    let value=form(#"[{"key":"enabled","type":"boolean","required":true},{"key":"detail","type":"string","required":true,"when":[{"key":"enabled","op":"eq","value":true}]},{"key":"more","type":"integer","when":[{"key":"detail","op":"neq","value":"skip"}]}]"#)
    let stale:[String:OpenCodeFormValue]=["enabled":.bool(false),"detail":.string("old"),"more":.number(3)]
    #expect(value.activeAnswer(stale)==["enabled":.bool(false)])
    #expect(throws:OpenCodeFormValidation.self){try value.validate(answer:stale)}
    try value.validate(answer:value.activeAnswer(stale))
    #expect(value.activeFields(answer:[:]).map(\.key)==["enabled"])
  }
  @Test func integerBooleanAndMultiselectBoundsStayDistinct() throws {
    let value=form(#"[{"key":"count","type":"integer","required":true,"minimum":1,"maximum":3},{"key":"flag","type":"boolean","required":true},{"key":"choices","type":"multiselect","required":true,"minItems":1,"maxItems":2,"options":[{"value":"a","label":"A"},{"value":"b","label":"B"}]}]"#)
    let valid:[String:OpenCodeFormValue]=["count":.number(2),"flag":.bool(false),"choices":.strings(["a"])]
    try value.validate(answer:valid)
    for (key,bad) in [("count",OpenCodeFormValue.number(1.5)),("flag",.number(1)),("choices",.strings(["c"])),("choices",.strings([]))]{
      var answer=valid;answer[key]=bad
      #expect(throws:OpenCodeFormValidation.self){try value.validate(answer:answer)}
    }
  }
  @Test func unsafeOrUnknownSemanticsRequireComputerHandling() {
    for field in [#"{"key":"x","type":"string","pattern":"(?<=a)b"}"#,#"{"key":"x","type":"string","hidden":true}"#,#"{"key":"x","type":"password"}"#,#"{"key":"x","type":"external","url":"https://accounts.example/authorize"}"#]{
      let value=form("["+field+"]")
      #expect(!value.supported)
      #expect(throws:OpenCodeFormValidation.self){try value.validate(answer:["x":.string("value")])}
    }
  }
  @Test func changedDefinitionsHaveDifferentFingerprintsAndUnsafeLinksAreNotOpened() throws {
    let a=form(#"[{"key":"x","type":"string"}]"#),b=form(#"[{"key":"x","type":"string","required":true}]"#)
    #expect(a.definitionFingerprint != b.definitionFingerprint)
    let unsafe=form(#"[{"key":"x","type":"external","url":"https://user:secret@example.test/path"}]"#)
    #expect(unsafe.fields[0].externalURL==nil)
    let safe=form(#"[{"key":"x","type":"external","url":"https://example.test/path"}]"#)
    #expect(safe.fields[0].externalURL?.host=="example.test")
  }
}
