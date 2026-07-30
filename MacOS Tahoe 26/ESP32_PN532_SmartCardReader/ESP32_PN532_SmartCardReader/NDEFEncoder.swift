//********************************************************************************************************//
// Nome Modulo: NDEFEncoder.swift
// Descrizione: Generatore e formattatore avanzato di flussi binari conformi allo standard NFC Forum NDEF.
//              Supporta la concatenazione dinamica di record multipli (Testo e URI).
//********************************************************************************************************//

import Foundation

enum NDEFType: String, CaseIterable, Identifiable {
    case url = "URI/URL"
    case text = "Testo"
    var id: String { self.rawValue }
}

struct NDEFWriteRecord: Identifiable {
    let id = UUID()
    var type: NDEFType = .url
    var value: String = ""
}

class NDEFEncoder {
    
    /**
     * Prende un array di record configurati dall'utente e genera il blocco binario TLV allineato a 4 byte
     */
    static func encodeMultipleRecords(records: [NDEFWriteRecord]) -> [UInt8] {
        var ndefMessageBytes: [UInt8] = []
        let validRecords = records.filter { !$0.value.isEmpty }
        
        guard !validRecords.isEmpty else { return [] }
        
        for (index, record) in validRecords.enumerated() {
            let isFirst = (index == 0)
            let isLast = (index == validRecords.count - 1)
            
            // Calcolo dei flag di controllo NDEF (MB, ME, CF=0, SR=1, IL=0, TNF=0x01 Well-Known)
            var headerByte: UInt8 = 0x01 // TNF predefinito
            if isFirst { headerByte |= 0x80 } // MB = 1
            if isLast  { headerByte |= 0x40 } // ME = 1
            headerByte |= 0x10                // SR = 1 (Short Record costantemente a 1 byte di lunghezza)
            
            switch record.type {
            case .url:
                if let uriBytes = compileURIRecord(header: headerByte, urlString: record.value) {
                    ndefMessageBytes.append(contentsOf: uriBytes)
                }
            case .text:
                if let textBytes = compileTextRecord(header: headerByte, textString: record.value) {
                    ndefMessageBytes.append(contentsOf: textBytes)
                }
            }
        }
        
        // Incapsulamento nel blocco di trasmissione TLV (Type-Length-Value) per la memoria dell'NTAG
        var tlvPayload: [UInt8] = []
        tlvPayload.append(0x03) // T: NDEF Message Type
        tlvPayload.append(UInt8(ndefMessageBytes.count & 0xFF)) // L: Lunghezza totale del messaggio NDEF
        tlvPayload.append(contentsOf: ndefMessageBytes) // V: Array di record concatenati
        tlvPayload.append(0xFE) // Terminatore del blocco TLV
        
        // Allineamento geometrico a pagine di 4 byte (Padding con 0x00)
        let paddingNeeded = (4 - (tlvPayload.count % 4)) % 4
        if paddingNeeded > 0 {
            tlvPayload.append(contentsOf: [UInt8](repeating: 0x00, count: paddingNeeded))
        }
        
        return tlvPayload
    }
    
    private static func compileURIRecord(header: UInt8, urlString: String) -> [UInt8]? {
        var uriBody = urlString
        var prefixCode: UInt8 = 0x00
        
        if urlString.hasPrefix("https://www.") { prefixCode = 0x02; uriBody = String(urlString.dropFirst(12)) }
        else if urlString.hasPrefix("http://www.") { prefixCode = 0x01; uriBody = String(urlString.dropFirst(11)) }
        else if urlString.hasPrefix("https://") { prefixCode = 0x04; uriBody = String(urlString.dropFirst(8)) }
        else if urlString.hasPrefix("http://") { prefixCode = 0x03; uriBody = String(urlString.dropFirst(7)) }
        else if urlString.hasPrefix("mailto:") { prefixCode = 0x06; uriBody = String(urlString.dropFirst(7)) }
        
        let bodyBytes = Array(uriBody.utf8)
        let payloadLength = bodyBytes.count + 1
        
        var record: [UInt8] = []
        record.append(header)
        record.append(0x01) // Type Length ("U")
        record.append(UInt8(payloadLength & 0xFF))
        record.append(0x55) // Type: "U"
        record.append(prefixCode)
        record.append(contentsOf: bodyBytes)
        return record
    }
    
    private static func compileTextRecord(header: UInt8, textString: String) -> [UInt8]? {
        let textBytes = Array(textString.utf8)
        let langBytes = Array("en".utf8) // Codice lingua predefinito standard
        let statusByte = UInt8(langBytes.count & 0x3F) // Specifica NDEF Text Status Byte
        
        let payloadLength = 1 + langBytes.count + textBytes.count
        
        var record: [UInt8] = []
        record.append(header)
        record.append(0x01) // Type Length ("T")
        record.append(UInt8(payloadLength & 0xFF))
        record.append(0x54) // Type: "T" (RTD_TEXT in ASCII)
        record.append(statusByte)
        record.append(contentsOf: langBytes)
        record.append(contentsOf: textBytes)
        return record
    }
}
