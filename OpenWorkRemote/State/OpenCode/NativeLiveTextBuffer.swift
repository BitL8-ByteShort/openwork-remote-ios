import Foundation
import OpenWorkRemoteCore

struct NativeLiveTextBuffer {
  enum Update{case ignored,updated,needsSnapshot}
  private struct Key:Hashable{let messageID:String;let ordinal:Int}
  private struct Value{var text:String;var streaming:Bool}
  private var values:[Key:Value]=[:]
  func text(messageID:String,ordinal:Int)->String?{values[Key(messageID:messageID,ordinal:ordinal)]?.text}
  mutating func receive(_ event:OpenCodeEvent)->Update {
    guard event.type.hasPrefix("session.text."),let id=event.data.assistantMessageID,let ordinal=event.data.ordinal else{return .ignored}
    let key=Key(messageID:id,ordinal:ordinal)
    switch event.type {
    case "session.text.started":values[key]=Value(text:"",streaming:true)
    case "session.text.delta":
      guard var value=values[key],value.streaming,let delta=event.data.delta else{return .needsSnapshot}
      guard value.text.utf8.count+delta.utf8.count<=262_144 else{values.removeValue(forKey:key);return .needsSnapshot}
      value.text+=delta;values[key]=value
    case "session.text.ended":
      guard let text=event.data.text,text.utf8.count<=262_144 else{values.removeValue(forKey:key);return .needsSnapshot}
      values[key]=Value(text:text,streaming:false)
    default:return .ignored
    }
    guard values.count<=64,values.values.reduce(0,{$0+$1.text.utf8.count})<=1_048_576 else{values.removeAll();return .needsSnapshot}
    return .updated
  }
  mutating func confirmed(by messages:[OpenCodeMessage]) {
    let byID=Dictionary(uniqueKeysWithValues:messages.map{($0.id,$0)})
    for (key,value) in values where !value.streaming {
      // Native ordinals count text fragments, independently of tools/reasoning.
      let texts=byID[key.messageID]?.content.filter{$0.type=="text"} ?? []
      if texts.indices.contains(key.ordinal),texts[key.ordinal].text==value.text{values.removeValue(forKey:key)}
    }
  }
  mutating func reset(){values.removeAll()}
}
