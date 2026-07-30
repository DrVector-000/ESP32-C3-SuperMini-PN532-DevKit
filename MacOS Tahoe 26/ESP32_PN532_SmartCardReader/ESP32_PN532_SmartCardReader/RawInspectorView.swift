//********************************************************************************************************//
// Nome Modulo: RawInspectorView.swift
// Descrizione: Sotto-vista SwiftUI per l'ispezione a basso livello dell'ATR e delle pagine di memoria.
//********************************************************************************************************//

import SwiftUI

struct RawInspectorView: View {
    @Bindable var viewModel: ReaderViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // AREA REGISTRAZIONE METADATI SMARTCARD (La sezione ripristinata)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Famiglia di Tag:")
                        .foregroundColor(.secondary)
                    Text(viewModel.detectedCardType)
                        .bold()
                        .foregroundColor(.blue)
                }
                
                HStack(spacing: 6) {
                    Text("Modello IC Estratto:")
                        .foregroundColor(.secondary)
                    Text(viewModel.icModelLabel)
                        .bold()
                        .foregroundColor(.purple)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Risposta ATR (Answer To Reset):")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                    
                    Text(viewModel.atrLabel)
                        .font(.system(.body, design: .monospaced))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            .cornerRadius(8)
            
            Divider()
            
            // AREA DI LETTURA MANUALE DELLE PAGINE VIA STEPPER
            VStack(alignment: .leading, spacing: 10) {
                Text("Ispezione Blocchi di Memoria")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    Text("Pagina Grezza Target:")
                    Text("\(viewModel.targetPageInput)")
                        .bold()
                        .frame(width: 24)
                    
                    Stepper("", value: $viewModel.targetPageInput, in: 0...250)
                        .labelsHidden()
                        .disabled(!viewModel.isDeviceConnected || viewModel.slotLabel != "Smartcard Rilevata")
                    
                    Button("Leggi Pagina/Blocco") {
                        viewModel.readSmartCardPage()
                    }
                    .disabled(!viewModel.isDeviceConnected || viewModel.slotLabel != "Smartcard Rilevata")
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Buffer Contenuto Ricevuto:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(viewModel.pageDataLabel)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                }
            }
            
            Spacer()
        }
        .padding(.top, 10)
    }
}
