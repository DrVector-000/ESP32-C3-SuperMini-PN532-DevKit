//********************************************************************************************************//
// Nome Modulo: ReaderViewModel.swift
// Descrizione: Gestore dello stato dell'applicazione. Sincronizza i dati tra l'engine seriale e la vista.
//********************************************************************************************************//

import Foundation
import Observation

@Observable
class ReaderViewModel {
    var connectionLabel: String = "Disconnesso"
    var slotLabel: String = "In attesa di smartcard..."
    var atrLabel: String = "-"
    var isDeviceConnected: Bool = false
    
    // Proprietà operative per la GUI e lo Stepper
    var pageDataLabel: String = "Nessun dato letto"
    var targetPageInput: Int = 4
    
    var availablePorts: [String] = []
    var selectedPort: String = ""
    var selectedBaudRate: Int = 115200
    let commonBaudRates: [Int] = [9600, 19200, 38400, 57600, 115200]
    
    var detectedCardType: String = "Sconosciuto"
    var icModelLabel: String = "Sconosciuto"

    private let ccidEngine = SerialCCIDEngine()
    private var messageSequence: UInt8 = 0

    // Nuove proprietà per la gestione NDEF
    var parsedNDEFRecords: [NDEFRecord] = []
    var isReadingNDEF: Bool = false
    
    private var ndefBufferAccumulator: [UInt8] = []
    private var ndefCurrentPageToRead: Int = 0
    private let ndefMaxPages = 36 // Intervallo esteso di scansione (pagine 4-39)

    // Nuove proprietà per la gestione della scrittura
    var recordsToWrite: [NDEFWriteRecord] = [NDEFWriteRecord(type: .url, value: "https://apple.com")]
    var writeStatusLabel: String = "Pronto per la scrittura"
    var isWritingNDEF: Bool = false
    
    // Nuova proprietà reattiva per memorizzare la cronologia dei log
    var logConsoleOutput: [String] = []

    private var ndefBytesToWrite: [UInt8] = []
    private var ndefCurrentPageToWrite: Int = 0
    private var ndefTotalPagesToWrite: Int = 0
    
    init() {
        refreshSerialPorts()
        // Registrazione del canale di ascolto per intercettare i byte di ritorno dell'APDU
        NotificationCenter.default.addObserver(self, selector: #selector(handleApduNotification(_:)), name: Notification.Name("ApduResponseReceived"), object: nil)
    }

    /**
     * Aggiunge una riga di testo alla console inserendo il timestamp esatto
     */
    func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        
        // Usiamo [weak self] dentro la chiusura asincrona per evitare retain cycle
        DispatchQueue.main.async { [weak self] in
            guard let strongSelf = self else { return }
            
            strongSelf.logConsoleOutput.append("[\(timestamp)] \(message)")
            
            // Limitiamo la console a 100 righe per non saturare la memoria RAM
            if strongSelf.logConsoleOutput.count > 100 {
                strongSelf.logConsoleOutput.removeFirst()
            }
        }
    }

    /**
     * Pulisce la console dei log
     */
    func clearLogConsole() {
        logConsoleOutput.removeAll()
    }
    
    /**
     * Aggiunge un nuovo slot vuoto nella lista dei record di scrittura della GUI
     */
    func addWriteRecordSlot() {
        recordsToWrite.append(NDEFWriteRecord(type: .url, value: ""))
    }
    
    /**
     * Rimuove un record specifico dall'elenco della GUI
     */
    func removeWriteRecordSlot(at index: Int) {
        if recordsToWrite.count > 1 {
            recordsToWrite.remove(at: index)
        }
    }
    
    /**
     * Prepara la sequenza di record multipli concatenati e avvia la scrittura a blocchi PC/SC
     */
    func startNDEFWritingSequence() {
        guard isDeviceConnected && slotLabel == "Smartcard Rilevata" else { return }
        
        isWritingNDEF = true
        writeStatusLabel = "Compilazione blocco multi-record..."
        
        // Generazione del flusso lineare accoppiato e allineato a 4 byte
        ndefBytesToWrite = NDEFEncoder.encodeMultipleRecords(records: recordsToWrite)
        
        guard !ndefBytesToWrite.isEmpty else {
            isWritingNDEF = false
            writeStatusLabel = "Errore: Inserisci almeno un valore"
            return
        }
        
        ndefCurrentPageToWrite = 4 // La scrittura inizia costantemente alla pagina 4
        ndefTotalPagesToWrite = ndefBytesToWrite.count / 4
        
        sendNextNDEFPageBlock()
    }
    
    private func sendNextNDEFPageBlock() {
        let byteIndex = (ndefCurrentPageToWrite - 4) * 4
        guard byteIndex < ndefBytesToWrite.count else { return }
        
        let pageChunk = Array(ndefBytesToWrite[byteIndex..<(byteIndex + 4)])
        messageSequence &+= 1
        
        // Composizione dell'APDU standard PC/SC Update Binary: FF D6 00 [Pagina] 04 [Dati]
        var updateApdu: [UInt8] = [0xFF, 0xD6, 0x00, UInt8(ndefCurrentPageToWrite & 0xFF), 0x04]
        updateApdu.append(contentsOf: pageChunk)
        
        // CORREZIONE: Tracciamo il comando di scrittura completo di payload esadecimale
        self.appendLog("▶️ INVIO APDU UPDATE NDEF (Page \(ndefCurrentPageToWrite)): [\(updateApdu.map { String(format: "%02X", $0) }.joined(separator: " "))]")
        
        writeStatusLabel = "Scrittura pagina \(ndefCurrentPageToWrite)..."
        ccidEngine.sendXfrBlock(sequence: messageSequence, apdu: updateApdu)
    }

    /**
     * Gestisce la risposta ad ogni comando di scrittura (chiamata dal motore seriale)
     */
    func processWriteBlockResponse(bytes: [UInt8]) {
        guard isWritingNDEF else { return }
        
        let sw2 = bytes[bytes.count - 1]
        let sw1 = bytes[bytes.count - 2]
        
        if sw1 == 0x90 && sw2 == 0x00 {
            ndefCurrentPageToWrite += 1
            let writtenPages = ndefCurrentPageToWrite - 4
            
            if writtenPages < ndefTotalPagesToWrite {
                // Procedi con la pagina successiva
                sendNextNDEFPageBlock()
            } else {
                // Catena completata con successo
                isWritingNDEF = false
                writeStatusLabel = "Scrittura Completata con Successo! (Pagine scritte: \(writtenPages))"
            }
        } else {
            isWritingNDEF = false
            writeStatusLabel = "Errore di scrittura hardware alla pagina \(ndefCurrentPageToWrite)"
        }
    }

    /**
     * Avvia la routine di scaricamento sequenziale della memoria per estrarre il blocco NDEF
     */
    func startNDEFReadingSequence() {
        guard isDeviceConnected && slotLabel == "Smartcard Rilevata" else { return }
        isReadingNDEF = true
        ndefBufferAccumulator.removeAll()
        ndefCurrentPageToRead = 4 // La memoria dati utente negli NTAG inizia sempre alla pagina 4
        
        // Richiede la prima pagina della sequenza
        requestPageForNDEF(page: ndefCurrentPageToRead)
    }
        
    private func requestPageForNDEF(page: Int) {
        messageSequence &+= 1
        
        let readApdu: [UInt8] = [0xFF, 0xB0, 0x00, UInt8(page & 0xFF), 0x04]
        
        // CORREZIONE: Passiamo la costante 'readApdu' definita sopra alla console di tracciamento
        self.appendLog("▶️ INVIO APDU SEQUENZA NDEF (Page \(page)): [\(readApdu.map { String(format: "%02X", $0) }.joined(separator: " "))]")
        
        ccidEngine.sendXfrBlock(sequence: messageSequence, apdu: readApdu)
    }

    /**
     * Integra questo controllo all'INTERNO del tuo vecchio metodo @objc private func handleApduNotification:
     * Inserisci questo blocco subito prima della decodifica del singolo pannello, per intercettare l'accumulatore.
     */
    func processNDEFByteChunk(bytes: [UInt8]) {
        let dataBytes = Array(bytes[0..<(bytes.count - 2)])
        ndefBufferAccumulator.append(contentsOf: dataBytes)
        
        ndefCurrentPageToRead += 1
        
        if ndefCurrentPageToRead < (4 + ndefMaxPages) {
            requestPageForNDEF(page: ndefCurrentPageToRead)
        } else {
            isReadingNDEF = false
            // Chiamata alla nuova utility di estrazione lineare multi-record
            parsedNDEFRecords = NDEFParser.parseMultipleRecords(bytes: ndefBufferAccumulator)
            
            // Se la collezione è vuota, popoliamo un record fittizio descrittivo per l'interfaccia utente
            if parsedNDEFRecords.isEmpty {
                parsedNDEFRecords.append(NDEFRecord(type: "Vuoto", payload: "Nessun messaggio o record NDEF valido rilevato all'interno della memoria utente."))
            }
        }
    }

    /**
     * Invia un comando APDU Read Binary per estrarre la pagina selezionata dallo Stepper
     */
    func readSmartCardPage() {
        guard isDeviceConnected else { return }
        
        messageSequence &+= 1
        
        // Costruzione dell'APDU standard PC/SC Read Binary: FF B0 00 [Pagina] 04
        let readApdu: [UInt8] = [0xFF, 0xB0, 0x00, UInt8(targetPageInput & 0xFF), 0x04]
        
        // CORREZIONE: Ora la variabile 'readApdu' è definita nello scope e passata al log
        self.appendLog("▶️ INVIO APDU COMANDO (Read Page \(targetPageInput)): [\(readApdu.map { String(format: "%02X", $0) }.joined(separator: " "))]")
        
        ccidEngine.sendXfrBlock(sequence: messageSequence, apdu: readApdu)
    }

    /**
     * Riceve ed elabora l'array di byte di ritorno dell'APDU isolando la Status Word (SW)
     */
    @objc private func handleApduNotification(_ notification: Notification) {
        guard let bytes = notification.object as? [UInt8], bytes.count >= 2 else { return }
        let hexStr = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        appendLog("◀️ RISPOSTA APDU CARTA: [\(hexStr)]")
            
        if isWritingNDEF {
                processWriteBlockResponse(bytes: bytes)
        } else if isReadingNDEF {
            processNDEFByteChunk(bytes: bytes)
        } else {
            let sw2 = bytes[bytes.count - 1]
            let sw1 = bytes[bytes.count - 2]
            
            guard sw1 == 0x90 && sw2 == 0x00 else { return }
            
            // La risposta hardware al comando NXP GET_VERSION è lunga esattamente 8 byte (+ 2 byte di SW = 10 byte totali)
            if bytes.count == 10 {
                // L'indice del modello di memoria (IC Chip Storage Size) si trova esattamente al 6° byte (indice 6)
                let storageSizeByte = bytes[6]
                
                switch storageSizeByte {
                case 0x0F:
                    icModelLabel = "IC Reale: NXP NTAG213 (144 Byte Utente)"
                case 0x11:
                    icModelLabel = "IC Reale: NXP NTAG215 (504 Byte Utente)"
                case 0x13:
                    icModelLabel = "IC Reale: NXP NTAG216 (888 Byte Utente)"
                default:
                    icModelLabel = "IC Rilevato: Famiglia NXP Ultralight (Size: \(String(format: "%02X", storageSizeByte)))"
                }
            } else {
                // Se la lunghezza è diversa, si tratta della normale risposta a 4 o 16 byte del comando Read Binary
                let dataBytes = Array(bytes[0..<(bytes.count - 2)])
                let hexString = dataBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                let asciiString = String(bytes: dataBytes, encoding: .ascii)?.replacingOccurrences(of: "\0", with: ".") ?? ""
                pageDataLabel = "HEX: [\(hexString)] | ASCII: \"\(asciiString)\""
            }
        }
    }

    /**
     * Aggiorna la lista delle porte seriali disponibili interrogando IOKit
     */
    func refreshSerialPorts() {
        // CORRETTO: Chiamata allineata alla firma statica di SerialEnumerator
        availablePorts = SerialEnumerator.enumerateSerialPorts()
        
        if let firstPort = availablePorts.first, selectedPort.isEmpty {
            selectedPort = firstPort
        }
    }

    func processConnectionToggle() {
        if isDeviceConnected {
            ccidEngine.disconnect()
            connectionLabel = "Disconnesso"
            slotLabel = "In attesa di smartcard..."
            atrLabel = "-"
            isDeviceConnected = false
        } else {
            guard !selectedPort.isEmpty else {
                connectionLabel = "Nessuna porta selezionata"
                return
            }
            configureEngineCallbacks()
            if ccidEngine.connect(to: selectedPort, baudRate: selectedBaudRate) {
                connectionLabel = "Connesso a \(selectedPort.components(separatedBy: "/").last ?? "")"
                isDeviceConnected = true
            } else {
                connectionLabel = "Errore di apertura"
            }
        }
    }
    
    /**
     * Configura i canali di callback in ingresso dal motore seriale CCID
     */
    /**
     * Configura i canali di callback asincroni in ingresso dal motore seriale CCID
     */
    func configureEngineCallbacks() {
        
        // 1. CALLBACK: Variazione di stato dello Slot Hardware (CCID 0x50)
        ccidEngine.onSlotStatusChanged = { [weak self] statusByte in
            guard let strongSelf = self else { return }
            
            // Output immediato nella console di Xcode per basso livello
            print("🚨 DEBUG SERIALE: Ricevuto pacchetto Slot Change (0x50) -> Valore Byte: [\(String(format: "%02X", statusByte))]")
            
            // Spostiamo la logica sul thread principale per aggiornare la UI osservabile
            DispatchQueue.main.async {
                if statusByte == 0x03 {
                    strongSelf.slotLabel = "Smartcard Rilevata"
                    strongSelf.appendLog("📥 EVENTO HARDWARE: Carta inserita nello slot")
                    
                    // Richiesta automatica dell'ATR forzando l'accensione logica della carta
                    strongSelf.messageSequence &+= 1
                    print("🚨 DEBUG SERIALE: Invio automatico CCID IccPowerOn (0x62) per richiedere ATR...")
                    strongSelf.appendLog("▶️ INVIO CCID COMANDO: PC_to_RDR_IccPowerOn (0x62)")
                    
                    strongSelf.ccidEngine.sendIccPowerOn(sequence: strongSelf.messageSequence)
                } else {
                    strongSelf.slotLabel = "Slot Vuoto"
                    strongSelf.atrLabel = "-"
                    strongSelf.detectedCardType = "Sconosciuto"
                    strongSelf.icModelLabel = "Sconosciuto"
                    strongSelf.parsedNDEFRecords.removeAll()
                    strongSelf.appendLog("📥 EVENTO HARDWARE: Carta rimossa dallo slot")
                }
            }
        }
        
        // 2. CALLBACK: Ricezione ed estrazione dell'ATR binario PC/SC Part 3 (CCID 0x80)
        ccidEngine.onAtrReceived = { [weak self] atrBytes in
            guard let strongSelf = self else { return }
            
            let hexFormattedString = atrBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            
            print("🚨 DEBUG SERIALE: INTERCETTATO PACCHETTO ATR DA ESP32! Byte totali: \(atrBytes.count)")
            print("🚨 DEBUG SERIALE: Payload esadecimale ATR grezzo -> [\(hexFormattedString)]")
            
            // Spostiamo l'elaborazione dei metadati e il rendering sulla UI
            DispatchQueue.main.async {
                strongSelf.atrLabel = hexFormattedString
                strongSelf.appendLog("💎 ATR RICEVUTO: [\(hexFormattedString)]")
                
                guard atrBytes.count > 14 else {
                    strongSelf.detectedCardType = "ATR non conforme PC/SC"
                    strongSelf.icModelLabel = "Dati insufficienti"
                    return
                }
                
                // Estrazione rigida degli indici PC/SC Contactless Part 3
                let sakByte: UInt8 = atrBytes[13]
                let uidLength: Int = Int(atrBytes[14])
                
                // Matrice decisionale ufficiale conforme NXP AN10833
                switch sakByte {
                case 0x00:
                    strongSelf.detectedCardType = "MIFARE Ultralight / NXP NTAG"
                    if uidLength == 7 {
                        strongSelf.icModelLabel = "IC: NTAG213 / NTAG215 / NTAG216"
                    } else {
                        strongSelf.icModelLabel = "IC: MIFARE Ultralight Legacy"
                    }
                    
                case 0x01:
                    strongSelf.detectedCardType = "MIFARE TNP3xxx"
                    strongSelf.icModelLabel = "IC: Bigliettazione speciale trasporti"
                    
                case 0x04:
                    strongSelf.detectedCardType = "MIFARE Classic 1K (Emulated)"
                    strongSelf.icModelLabel = "IC: Magic Tag UID modificabile"
                    
                case 0x08:
                    if uidLength == 7 {
                        strongSelf.detectedCardType = "MIFARE Classic 1K (7B UID)"
                        strongSelf.icModelLabel = "IC: NXP S50 (Generazione con UID lungo)"
                    } else {
                        strongSelf.detectedCardType = "MIFARE Classic 1K"
                        strongSelf.icModelLabel = "IC: NXP S50 standard"
                    }
                    
                case 0x09:
                    strongSelf.detectedCardType = "MIFARE Mini"
                    strongSelf.icModelLabel = "IC: NXP S20 (Capacità 320 Byte)"
                    
                case 0x10:
                    strongSelf.detectedCardType = "MIFARE Plus S"
                    strongSelf.icModelLabel = "IC: Plus S 2K/4K in SL2"
                    
                case 0x11:
                    strongSelf.detectedCardType = "MIFARE Plus X"
                    strongSelf.icModelLabel = "IC: Plus X 2K/4K in SL2"
                    
                case 0x18:
                    if uidLength == 7 {
                        strongSelf.detectedCardType = "MIFARE Classic 4K (7B UID)"
                        strongSelf.icModelLabel = "IC: NXP S70 (Generazione con UID lungo)"
                    } else {
                        strongSelf.detectedCardType = "MIFARE Classic 4K"
                        strongSelf.icModelLabel = "IC: NXP S70 standard"
                    }
                    
                case 0x20:
                    strongSelf.detectedCardType = "ISO/IEC 14443-4 SmartCard"
                    if uidLength == 7 {
                        strongSelf.icModelLabel = "IC: MIFARE DESFire (EV1/EV2/EV3)"
                    } else if uidLength == 4 {
                        strongSelf.icModelLabel = "IC: Tessera Sanitaria (TS-CNS) / CIE / EMV"
                    } else {
                        strongSelf.icModelLabel = "IC: SmartCard Microprocessata Alta Sicurezza"
                    }
                    
                case 0x24:
                    strongSelf.detectedCardType = "MIFARE DESFire (Native Mode)"
                    strongSelf.icModelLabel = "IC: DESFire in configurazione non-ISO"
                    
                case 0x28:
                    strongSelf.detectedCardType = "MIFARE Plus / Dual Interface"
                    strongSelf.icModelLabel = "IC: Emulazione Classic + ISO 14443-4 attivo"
                    
                case 0x38:
                    strongSelf.detectedCardType = "MIFARE Plus S (SL3)"
                    strongSelf.icModelLabel = "IC: Plus S in modalità Sicurezza Layer 3"
                    
                case 0x88:
                    strongSelf.detectedCardType = "MIFARE Classic 1K (Infineon)"
                    strongSelf.icModelLabel = "IC: Chip compatibile Infineon"
                    
                case 0x98:
                    strongSelf.detectedCardType = "MIFARE Classic 4K (Infineon)"
                    strongSelf.icModelLabel = "IC: Chip compatibile Infineon"
                    
                default:
                    strongSelf.detectedCardType = "Tag ISO 14443A Alternativo"
                    strongSelf.icModelLabel = String(format: "SAK Hardware: 0x%02X", sakByte)
                }
            }
        }
    }

    /**
     * Invia un comando Pass-Through per richiedere l'identificazione dell'IC (NXP GET_VERSION)
     */
    func fetchHardwareICVersion() {
        guard isDeviceConnected else { return }
        
        messageSequence &+= 1
        // Struttura APDU Pass-Through conforme PC/SC:
        // FF 00 00 00 -> Prefisso comando lettore
        // 02          -> Lunghezza del blocco dati RF successivo (2 byte)
        // 60          -> Comando GET_VERSION nativo del silicio NXP
        // 00          -> Byte RFU
        let getVersionApdu: [UInt8] = [0xFF, 0x00, 0x00, 0x00, 0x02, 0x60, 0x00]
        
        ccidEngine.sendXfrBlock(sequence: messageSequence, apdu: getVersionApdu)
    }

    
}
