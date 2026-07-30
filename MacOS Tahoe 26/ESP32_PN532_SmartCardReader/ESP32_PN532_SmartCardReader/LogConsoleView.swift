//********************************************************************************************************//
// Nome Modulo: LogConsoleView.swift
// Descrizione: Sotto-vista scorrevole monospaziata per il tracciamento dei pacchetti binari CCID/APDU.
//********************************************************************************************************//

import SwiftUI

//********************************************************************************************************//
// Nome Componente: LogConsoleView
// Descrizione: Sotto-vista scorrevole monospaziata per il tracciamento dei pacchetti binari CCID/APDU.
//              Abilita la selezione del testo per consentire la copia dei dati diagnostici.
//********************************************************************************************************//
struct LogConsoleView: View {
    let logs: [String]
    let onClear: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Console di Diagnostica Transazioni APDU", systemImage: "terminal")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: onClear) {
                    Text("Cancella Log").font(.caption2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if logs.isEmpty {
                            Text("In attesa di transazioni hardware...")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.gray)
                        } else {
                            ForEach(logs.indices, id: \.self) { index in
                                Text(logs[index])
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(getLogColor(logs[index]))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                            // SBLOCCO COPIA: Permette di selezionare col mouse e copiare (Cmd+C) le righe di log
                            .textSelection(.enabled)
                        }
                    }
                    .padding(8)
                }
                .frame(maxWidth: .infinity, minHeight: 110, maxHeight: 150)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
                .onChange(of: logs.count) {
                    if !logs.isEmpty {
                        proxy.scrollTo(logs.count - 1, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private func getLogColor(_ log: String) -> Color {
        if log.contains("▶️") { return .purple }      // Comandi Host -> Card
        if log.contains("◀️") { return .green }       // Risposte Card -> Host
        if log.contains("💎") { return .blue }        // Risposte ATR dell'hardware
        if log.contains("EVENTO") { return .orange }   // Notifiche fisiche dello Slot
        return .primary
    }
}
