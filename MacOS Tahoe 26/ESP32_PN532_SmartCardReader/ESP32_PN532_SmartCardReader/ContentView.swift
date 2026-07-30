import SwiftUI

struct ContentView: View {
    @State private var viewModel = ReaderViewModel()
    
    var body: some View {
        @Bindable var viewModel = viewModel
        
        HStack(spacing: 0) {
            ControlSidebarView(viewModel: viewModel)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 24) {
                    StatusIndicatorView(title: "Hardware", value: viewModel.connectionLabel, isActive: viewModel.isDeviceConnected)
                    StatusIndicatorView(title: "Stato Slot", value: viewModel.slotLabel, isActive: viewModel.slotLabel == "Smartcard Rilevata")
                }
                
                TabView {
                    RawInspectorView(viewModel: viewModel)
                        .tabItem { Label("Raw Inspector", systemImage: "cpu") }
                    
                    NdefReaderView(viewModel: viewModel)
                        .tabItem { Label("NDEF Reader", systemImage: "doc.plaintext") }
                    
                    NdefWriterView(viewModel: viewModel)
                        .tabItem { Label("NDEF Writer", systemImage: "square.and.pencil") }
                }

                // ==================================================================
                // INSERIMENTO CONSOLE LOG: Agganciata stabilmente in fondo alla
                // scocca centrale
                // ==================================================================
                Divider()
                LogConsoleView(logs: viewModel.logConsoleOutput, onClear: { viewModel.clearLogConsole() })
                // ==================================================================
 
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 720, minHeight: 380)
    }
}

#Preview {
    ContentView()
}
