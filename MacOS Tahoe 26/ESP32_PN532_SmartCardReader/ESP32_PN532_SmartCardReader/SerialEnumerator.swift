//********************************************************************************************************//
// Nome Modulo: SerialEnumerator.swift
// Descrizione: Servizio IOKit per l'enumerazione e l'individuazione automatica delle porte USB-Serial.
//********************************************************************************************************//

import Foundation
import IOKit
import IOKit.serial

class SerialEnumerator {
    
    /**
     * Recupera l'elenco dei percorsi BSD delle porte seriali attive sul Mac
     */
    static func enumerateSerialPorts() -> [String] {
        var ports: [String] = []
        
        // 1. Creazione del dizionario di matching CoreFoundation per i servizi seriali BSD
        guard let matchingDict = IOServiceMatching(kIOSerialBSDServiceValue) else {
            return ports
        }
        
        // CORREZIONE CRUCIALE: Convertiamo (cast) il dizionario CFMutableDictionary in un NSMutableDictionary.
        // Questo sblocca legalmente l'uso delle parentesi quadre o del metodo setValue senza rompere i vincoli di Swift.
        let mutableDict = matchingDict as NSMutableDictionary
        mutableDict[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes
        
        // 2. Creazione dell'iteratore IOKit per scansionare l'albero hardware del Mac
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        
        guard result == KERN_SUCCESS else {
            return ports
        }
        
        // 3. Ciclo di scansione delle porte individuate dall'iteratore
        var modemService = IOIteratorNext(iterator)
        while modemService != 0 {
            // Estrazione della proprietà BSD Path (es. /dev/cu.usbserial-...)
            if let bsdPathAsCFString = IORegistryEntryCreateCFProperty(modemService,
                                                                       kIOCalloutDeviceKey as CFString,
                                                                       kCFAllocatorDefault,
                                                                       0) {
                let bsdPath = bsdPathAsCFString.takeRetainedValue() as! String
                ports.append(bsdPath)
            }
            
            IOObjectRelease(modemService)
            modemService = IOIteratorNext(iterator)
        }
        
        IOObjectRelease(iterator)
        return ports
    }
}
