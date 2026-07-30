//********************************************************************************************************//
// Nome Modulo: SerialCCIDEngine.swift (Aggiornato - No Deadlock)
// Descrizione: Gestore per la comunicazione seriale POSIX. Include la lettura non bloccante.
//********************************************************************************************************//

import Foundation

class SerialCCIDEngine {
    private var fileDescriptor: Int32 = -1
    private var isReading = false
    private let readQueue = DispatchQueue(label: "it.smartcard.readQueue", qos: .userInitiated)
    
    var onSlotStatusChanged: ((UInt8) -> Void)?
    var onAtrReceived: (([UInt8]) -> Void)?
    
    func connect(to portPath: String, baudRate: Int) -> Bool {
        // Manteniamo O_NONBLOCK attivo per consentire la disconnessione immediata
        fileDescriptor = open(portPath, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fileDescriptor != -1 else { return false }
        
        var options = termios()
        tcgetattr(fileDescriptor, &options)
        
        let speed: speed_t
        switch baudRate {
        case 9600:   speed = speed_t(B9600)
        case 19200:  speed = speed_t(B19200)
        case 38400:  speed = speed_t(B38400)
        case 57600:  speed = speed_t(B57600)
        case 115200: speed = speed_t(B115200)
        default:     speed = speed_t(B115200)
        }
        
        cfsetispeed(&options, speed)
        cfsetospeed(&options, speed)
        
        options.c_cflag &= ~tcflag_t(PARENB)
        options.c_cflag &= ~tcflag_t(CSTOPB)
        options.c_cflag &= ~tcflag_t(CSIZE)
        options.c_cflag |= tcflag_t(CS8)
        options.c_cflag |= tcflag_t(CREAD | CLOCAL)
        options.c_lflag &= ~tcflag_t(ICANON | ECHO | ECHOE | ISIG)
        options.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY | INPCK | ISTRIP)
        options.c_oflag &= ~tcflag_t(OPOST)
        
        tcsetattr(fileDescriptor, TCSANOW, &options)
        tcflush(fileDescriptor, TCIOFLUSH)
        
        startReadingThread()
        return true
    }
    
    private func startReadingThread() {
        isReading = true
        readQueue.async { [weak self] in
            var readBuffer = [UInt8](repeating: 0, count: 512)
            var streamAccumulator = [UInt8]()
            
            while let strongSelf = self, strongSelf.isReading {
                let bytesRead = read(strongSelf.fileDescriptor, &readBuffer, readBuffer.count)
                
                if bytesRead > 0 {
                    let chunk = Array(readBuffer[0..<bytesRead])
                    streamAccumulator.append(contentsOf: chunk)
                    strongSelf.parseCcidStream(&streamAccumulator)
                } else if bytesRead == -1 {
                    let err = errno
                    // Se l'errore è dovuto alla mancanza temporanea di dati, continuiamo senza bloccare
                    if err != EAGAIN && err != EWOULDBLOCK {
                        print("[POSIX] Errore di lettura critico: \(err)")
                        break
                    }
                }
                
                // Un micropaused ridotto a 5ms garantisce massima reattività e zero carico sulla CPU
                usleep(5000)
            }
            print("[POSIX] Thread di lettura seriale terminato correttamente.")
        }
    }
    
    private func parseCcidStream(_ buffer: inout [UInt8]) {
        while !buffer.isEmpty {
            let messageType = buffer[0]
            
            if messageType == 0x50 {
                guard buffer.count >= 2 else { return }
                let status = buffer[1]
                buffer.removeFirst(2)
                
                DispatchQueue.main.async {
                    self.onSlotStatusChanged?(status)
                }
            }             else if messageType == 0x80 {
                guard buffer.count >= 10 else { return }
                
                let payloadLength = Int(buffer[1]) | (Int(buffer[2]) << 8) | (Int(buffer[3]) << 16) | (Int(buffer[4]) << 24)
                let fullMessageLength = 10 + payloadLength
                
                guard buffer.count >= fullMessageLength else { return }
                
                let payloadData = Array(buffer[10..<fullMessageLength])
                buffer.removeFirst(fullMessageLength)
                
                DispatchQueue.main.async {
                    // Verifichiamo se si tratta della risposta dell'ATR (lunghezza tipica > 10)
                    // o della risposta di un comando APDU (che chiude sempre con 2 byte di Status Word)
                    if payloadData.count == 22 || payloadData.first == 0x3B {
                        self.onAtrReceived?(payloadData)
                    } else {
                        // Inoltra la risposta dell'APDU generica a un callback dedicato
                        NotificationCenter.default.post(name: Notification.Name("ApduResponseReceived"), object: payloadData)
                    }
                }
            } else {
                buffer.removeFirst()
            }
        }
    }
    
    func sendIccPowerOn(sequence: UInt8) {
        guard fileDescriptor != -1 else { return }
        var header = [UInt8](repeating: 0, count: 10)
        header[0] = 0x62
        header[6] = sequence
        write(fileDescriptor, header, header.count)
    }
    
    func disconnect() {
        // Cambiare questa variabile forza l'uscita immediata dal ciclo del thread
        isReading = false
        
        // Un piccolo delay assicura che il thread esca dal ciclo prima di chiudere il file descriptor
        usleep(10000)
        
        if fileDescriptor != -1 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }
    
    /**
     * Trasmette un comando PC_to_RDR_XfrBlock (0x6F) contenente un pacchetto APDU verso l'hardware
     */
    func sendXfrBlock(sequence: UInt8, apdu: [UInt8]) {
        guard fileDescriptor != -1 else { return }
        
        let payloadLength = apdu.count
        var packet = [UInt8](repeating: 0, count: 10 + payloadLength)
        
        // Costruzione dell'header CCID a 10 byte
        packet[0] = 0x6F // Message Type: PC_to_RDR_XfrBlock
        packet[1] = UInt8(payloadLength & 0xFF) // Lunghezza payload (Little Endian)
        packet[2] = UInt8((payloadLength >> 8) & 0xFF)
        packet[3] = UInt8((payloadLength >> 16) & 0xFF)
        packet[4] = UInt8((payloadLength >> 24) & 0xFF)
        packet[5] = 0x00 // bSlot (Slot 0)
        packet[6] = sequence // bSeq (Numero di sequenza progressivo)
        packet[7] = 0x00 // bBWI (Extension timeout)
        packet[8] = 0x00 // wLevelParameter (Little Endian)
        packet[9] = 0x00
        
        // Iniezione dei byte dell'APDU subito dopo l'header
        for i in 0..<payloadLength {
            packet[10 + i] = apdu[i]
        }
        
        // Scrittura atomica sul descrittore di file della porta seriale
        write(fileDescriptor, packet, packet.count)
    }

}
