//********************************************************************************************************//
// Nome Modulo: SubViews.swift
// Descrizione: Moduli grafici secondari (Sidebar e Indicatori) de-clutterizzati dalla vista principale.
//********************************************************************************************************//

import SwiftUI

struct ControlSidebarView: View {
    @Bindable var viewModel: ReaderViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CONNESSIONE")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Porta Seriale:")
                    Spacer()
                    Button(action: { viewModel.refreshSerialPorts() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isDeviceConnected)
                }
                
                Picker("", selection: $viewModel.selectedPort) {
                    if viewModel.availablePorts.isEmpty {
                        Text("Nessun dispositivo").tag("")
                    } else {
                        ForEach(viewModel.availablePorts, id: \.self) { port in
                            Text(port.components(separatedBy: "/").last ?? port).tag(port)
                        }
                    }
                }
                .labelsHidden()
                .disabled(viewModel.isDeviceConnected)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Baud Rate:")
                Picker("", selection: $viewModel.selectedBaudRate) {
                    ForEach(viewModel.commonBaudRates, id: \.self) { baud in
                        Text("\(baud) bps").tag(baud)
                    }
                }
                .labelsHidden()
                .disabled(viewModel.isDeviceConnected)
            }
            
            Spacer()
            
            Button(action: { viewModel.processConnectionToggle() }) {
                Text(viewModel.isDeviceConnected ? "Sconnetti" : "Connetti")
                    .bold()
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(viewModel.isDeviceConnected ? Color.red : Color.blue)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 220)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

//********************************************************************************************************//
// Nome Componente: StatusIndicatorView
// Descrizione: Sotto-vista riutilizzabile per gli indicatori professionali di stato con micro-LED.
//********************************************************************************************************//
struct StatusIndicatorView: View {
    let title: String
    let value: String
    let isActive: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                // Micro-LED dinamico: Verde se attivo, Grigio se disattivato
                Circle()
                    .fill(isActive ? Color.green : Color.gray.opacity(0.6))
                    .frame(width: 8, height: 8)
                
                Text(value)
                    .font(.body)
                    .fontWeight(.medium)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 180, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
    }
}
