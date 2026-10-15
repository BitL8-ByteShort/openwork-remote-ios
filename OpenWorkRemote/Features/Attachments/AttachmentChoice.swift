import SwiftUI

struct AttachmentChoice: View {
  let label: String
  let symbol: String
  nonisolated init(_ label: String, symbol: String) { self.label = label; self.symbol = symbol }
  var body: some View {
    HStack { Label(label,systemImage:symbol).font(.headline); Spacer(); Image(systemName:"chevron.right") }
      .frame(minHeight:44).padding(.horizontal,16).padding(.vertical,8)
      .foregroundStyle(Theme.ink).background(Theme.raised,in:RoundedRectangle(cornerRadius:18))
      .overlay(RoundedRectangle(cornerRadius:18).stroke(Theme.line))
  }
}

