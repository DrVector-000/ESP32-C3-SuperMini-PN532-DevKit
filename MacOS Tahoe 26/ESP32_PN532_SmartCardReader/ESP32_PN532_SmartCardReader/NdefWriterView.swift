//********************************************************************************************************//
// Nome Modulo: NdefWriterView.swift
// Descrizione: Interfaccia utente grafica in SwiftUI per la composizione e la scrittura multi-record NDEF.
//********************************************************************************************************//

import SwiftUI

struct NdefWriterView: View {
    @Bindable var viewModel: ReaderViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Composizione Messaggio NDEF").font(.headline).foregroundColor(.secondary)
                Spacer()
                
                // Pulsante per aggiungere a caldo un nuovo campo record
                Button(action: { viewModel.addWriteRecordSlot() }) {
                    Label("Aggiungi Campo", systemImage: "plus.circle")
                }
                .disabled(viewModel.isWritingNDEF || !viewModel.isDeviceConnected)
            }
            
            // Lista scorrevole dei record in fase di compilazione
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(viewModel.recordsToWrite.enumerated()), id: \.element.id) { index, _ in
                        HStack(spacing: 12) {
                            // Selezione Tipo Record
                            Picker("", selection: $viewModel.recordsToWrite[index].type) {
                                ForEach(NDEFType.allCases) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            .frame(width: 90)
                            .labelsHidden()
                            .disabled(viewModel.isWritingNDEF || !viewModel.isDeviceConnected)
                            
                            // Campo di immissione testo
                            TextField(viewModel.recordsToWrite[index].type == .url ? "https://..." : "Inserisci nota di testo", text: $viewModel.recordsToWrite[index].value)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .disabled(viewModel.isWritingNDEF || !viewModel.isDeviceConnected)
                            
                            // Pulsante Elimina riga (nascondi se è l'unica riga presente)
                            if viewModel.recordsToWrite.count > 1 {
                                Button(action: { viewModel.removeWriteRecordSlot(at: index) }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                                .disabled(viewModel.isWritingNDEF || !viewModel.isDeviceConnected)
                            }
                        }
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                        .cornerRadius(6)
                    }
                }
                .padding(.trailing, 2)
            }
            .frame(maxHeight: 180)
            
            Divider()
            
            // Barra comandi e di stato di scrittura finale
            HStack(spacing: 16) {
                Button(action: { viewModel.startNDEFWritingSequence() }) {
                    HStack {
                        Image(systemName: "square.and.pencil")
                        Text(viewModel.isWritingNDEF ? "Scrittura in corso..." : "Scrivi Blocco sul Tag NTAG")
                    }
                    .bold()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .disabled(!viewModel.isDeviceConnected || viewModel.slotLabel != "Smartcard Rilevata" || viewModel.isWritingNDEF)
                
                Text(viewModel.writeStatusLabel)
                    .font(.body).fontWeight(.medium)
                    .foregroundColor(viewModel.writeStatusLabel.contains("Successo") ? .green : .primary)
            }
            Spacer()
        }
        .padding(.top, 10)
    }
}
