import SwiftUI

struct NdefReaderView: View {
    @Bindable var viewModel: ReaderViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(action: { viewModel.startNDEFReadingSequence() }) {
                    HStack {
                        Image(systemName: "arrow.down.doc")
                        Text(viewModel.isReadingNDEF ? "Scansione Memoria In Corso..." : "Analizza Messaggio NDEF")
                    }.bold().padding(.horizontal, 12).padding(.vertical, 6)
                }
                .disabled(!viewModel.isDeviceConnected || viewModel.slotLabel != "Smartcard Rilevata" || viewModel.isReadingNDEF)
                
                if !viewModel.parsedNDEFRecords.isEmpty && !viewModel.isReadingNDEF {
                    Text("Trovati \(viewModel.parsedNDEFRecords.count) Record").font(.subheadline).foregroundColor(.secondary)
                }
            }
            
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(viewModel.parsedNDEFRecords) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: record.type == "URI/URL" ? "link" : "text.alignleft")
                                    .foregroundColor(record.type == "URI/URL" ? .blue : .green)
                                Text(record.type.uppercased()).font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                            }
                            Text(record.payload)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color(NSColor.windowBackgroundColor))
                                .cornerRadius(6)
                        }
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                        .cornerRadius(8)
                    }
                }.padding(.trailing, 2)
            }
        }
        .padding(.top, 10)
    }
}
