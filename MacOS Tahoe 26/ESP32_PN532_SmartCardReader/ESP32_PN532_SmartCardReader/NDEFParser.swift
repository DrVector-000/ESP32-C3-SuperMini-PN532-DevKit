//********************************************************************************************************//
// Nome Modulo: NDEFParser.swift
// Descrizione: Utility avanzata per il parsing di messaggi NDEF multi-record su tag contactless.
//********************************************************************************************************//

import Foundation

struct NDEFRecord: Identifiable {
    let id = UUID()
    var type: String       // "Testo", "URI/URL", o "Sconosciuto"
    var payload: String    // Il contenuto decodificato
}

class NDEFParser {
    
    /**
     * Analizza l'intera memoria utente estratta e restituisce un array di tutti i record NDEF trovati
     */
    static func parseMultipleRecords(bytes: [UInt8]) -> [NDEFRecord] {
        var detectedRecords: [NDEFRecord] = []
        guard bytes.count > 4 else { return detectedRecords }
        
        var index = 0
        
        // Scansione iniziale per localizzare il blocco NDEF TLV (Type-Length-Value)
        while index < bytes.count {
            let tlvType = bytes[index]
            
            if tlvType == 0x03 { // Trovato il contenitore NDEF Message
                guard index + 1 < bytes.count else { return detectedRecords }
                let ndefLength = Int(bytes[index + 1])
                
                let startIndex = index + 2
                let endIndex = startIndex + ndefLength
                
                guard endIndex <= bytes.count else { return detectedRecords }
                let ndefPayload = Array(bytes[startIndex..<endIndex])
                
                // Avvia il parsing della catena di record interni al payload NDEF
                detectedRecords = decodeNDEFMessageChain(payload: ndefPayload)
                return detectedRecords
            } else if tlvType == 0x00 { // Padding Null TLV
                index += 1
            } else if tlvType == 0xFE { // Terminatore anticipato
                return detectedRecords
            } else { // Salto di TLV proprietari o di blocco
                guard index + 1 < bytes.count else { return detectedRecords }
                let length = Int(bytes[index + 1])
                index += 2 + length
            }
        }
        return detectedRecords
    }
    
    /**
     * Naviga sequenzialmente all'interno del payload NDEF estraendo i singoli record fino alla fine del blocco
     */
    private static func decodeNDEFMessageChain(payload: [UInt8]) -> [NDEFRecord] {
        var records: [NDEFRecord] = []
        var cursor = 0
        
        while cursor < payload.count {
            guard cursor + 2 < payload.count else { break }
            
            let header = payload[cursor]
            let sr = (header & 0x10) != 0 // Flag Short Record (1 = Lunghezza payload espressa in 1 byte)
            let tnf = header & 0x07       // Type Name Format (0x01 = Well-Known Type)
            
            let typeLength = Int(payload[cursor + 1])
            
            var payloadLength = 0
            var headerOffset = 0
            
            if sr {
                // Short Record: la lunghezza del payload occupa solo 1 byte (indice cursor + 2)
                payloadLength = Int(payload[cursor + 2])
                headerOffset = 3
            } else {
                // Normal Record: la lunghezza occupa 4 byte (specifiche estese NDEF)
                guard cursor + 5 < payload.count else { break }
                payloadLength = Int(payload[cursor + 2]) << 24 |
                                Int(payload[cursor + 3]) << 16 |
                                Int(payload[cursor + 4]) << 8  |
                                Int(payload[cursor + 5])
                headerOffset = 6
            }
            
            // Verifica la presenza dell'ID se il flag IL (ID Length) è attivo nell'header
            let il = (header & 0x08) != 0
            if il {
                headerOffset += 1 // Salta il byte aggiuntivo dedicato alla lunghezza dell'ID
            }
            
            let typeStartIndex = cursor + headerOffset
            let typeEndIndex = typeStartIndex + typeLength
            let payloadStartIndex = typeEndIndex
            let payloadEndIndex = payloadStartIndex + payloadLength
            
            // Controllo di sicurezza sui limiti fisici dell'array prima dell'estrazione
            guard payloadEndIndex <= payload.count else { break }
            
            let recordTypeBytes = Array(payload[typeStartIndex..<typeEndIndex])
            let recordPayloadBytes = Array(payload[payloadStartIndex..<payloadEndIndex])
            
            let recordTypeStr = String(bytes: recordTypeBytes, encoding: .ascii) ?? ""
            
            // Decodifica formale del payload in base al tipo RTD (Record Type Definition)
            if tnf == 0x01 {
                if recordTypeStr == "T" { // RTD Text
                    if let textRecord = parseTextRecord(payloadBytes: recordPayloadBytes) {
                        records.append(textRecord)
                    }
                } else if recordTypeStr == "U" { // RTD URI
                    if let uriRecord = parseUriRecord(payloadBytes: recordPayloadBytes) {
                        records.append(uriRecord)
                    }
                } else {
                    records.append(NDEFRecord(type: "Well-Known Alternativo", payload: "Tipo: \(recordTypeStr), Lunghezza: \(payloadLength) byte"))
                }
            } else {
                records.append(NDEFRecord(type: "Sconosciuto", payload: "Formato TNF \(tnf) non supportato"))
            }
            
            // Spostamento del cursore all'inizio dell'eventuale record successivo
            cursor = payloadEndIndex
        }
        
        return records
    }
    
    private static func parseTextRecord(payloadBytes: [UInt8]) -> NDEFRecord? {
        guard !payloadBytes.isEmpty else { return nil }
        let statusByte = payloadBytes[0]
        let langLength = Int(statusByte & 0x3F)
        
        let textStartIndex = 1 + langLength
        guard textStartIndex <= payloadBytes.count else { return nil }
        
        let textBytes = Array(payloadBytes[textStartIndex..<payloadBytes.count])
        let textStr = String(bytes: textBytes, encoding: .utf8) ?? "Errore stringa UTF-8"
        return NDEFRecord(type: "Testo", payload: textStr)
    }
    
    private static func parseUriRecord(payloadBytes: [UInt8]) -> NDEFRecord? {
        guard !payloadBytes.isEmpty else { return nil }
        let prefixCode = payloadBytes[0]
        
        var prefix = ""
        switch prefixCode {
        case 0x01: prefix = "http://www."
        case 0x02: prefix = "https://www."
        case 0x03: prefix = "http://"
        case 0x04: prefix = "https://"
        case 0x06: prefix = "mailto:"
        default: prefix = ""
        }
        
        let urlBytes = Array(payloadBytes[1..<payloadBytes.count])
        let urlStr = prefix + (String(bytes: urlBytes, encoding: .utf8) ?? "")
        return NDEFRecord(type: "URI/URL", payload: urlStr)
    }
}
