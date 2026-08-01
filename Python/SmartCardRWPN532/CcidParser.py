#**************************************************************************************#
# Nome Modulo: CcidParser.py
# Descrizione: Helper specifico per il parsing e la decodifica dei pacchetti CCID PC/SC.
#**************************************************************************************#

class CcidResult:
    """Oggetto contenitore per trasferire i dati elaborati verso la View."""
    def __init__(self):
        self.event_type = None      
        self.slot_status = None     
        self.hex_payload = ""       
        self.hex_uid = "-"          
        self.hex_atr = "-"          
        self.ascii_payload = ""
        self.tag_family = "-"       
        self.log_message = ""       
        self.bytes_consumed = 0     

class CcidParser:
    @staticmethod
    def parse_stream(packet, start_index=0):
        """
        Analizza il buffer di byte a partire da un indice specifico.
        Ritorna un oggetto CcidResult.
        """
        result = CcidResult()
        if start_index >= len(packet):
            return result

        msg_type = packet[start_index]

        # -----------------------------------------------------------------
        # CASO 1: NOTIFICA VARIAZIONE SLOT (CCID 0x50 - NotifySlotChange)
        # -----------------------------------------------------------------
        if msg_type == 0x50 and (start_index + 1) < len(packet):
            status_byte = packet[start_index + 1]
            result.event_type = "SLOT_CHANGE"
            result.slot_status = status_byte
            result.bytes_consumed = 2
            
            if status_byte == 0x03:
                result.log_message = "📥 EVENTO HARDWARE: Carta inserita nello slot"
            elif status_byte == 0x02:
                result.log_message = "📥 EVENTO HARDWARE: Carta rimossa dallo slot"
            return result

        # -----------------------------------------------------------------
        # CASO 2: BLOCCO DATI ATR / RISPOSTE APDU (CCID 0x80 - DataBlock)
        # -----------------------------------------------------------------
        elif msg_type == 0x80 and (start_index + 9) < len(packet):
            # Ricostruzione della lunghezza del payload a 32-bit (Little Endian)
            payload_len = (packet[start_index + 1] | 
                           (packet[start_index + 2] << 8) | 
                           (packet[start_index + 3] << 16) | 
                           (packet[start_index + 4] << 24))

            # Verifica se l'intero pacchetto è arrivato completamente
            if (start_index + 10 + payload_len) <= len(packet):
                payload_bytes = packet[start_index + 10 : start_index + 10 + payload_len]
                result.hex_payload = " ".join(f"{b:02X}" for b in payload_bytes)
                result.bytes_consumed = 10 + payload_len

                # Sotto-caso A: Il pacchetto inizia con 0x3B -> È l'ATR ufficiale [NFC-1]
                if len(payload_bytes) > 0 and payload_bytes[0] == 0x3B:
                    result.event_type = "ATR"
                    result.hex_atr = result.hex_payload
                    result.log_message = f"💎 ATR RICEVUTO: [{result.hex_payload}]"

                    # Estrazione e decodifica parametri PC/SC Contactless Part 3
                    if len(payload_bytes) > 14:
                        sak_byte = payload_bytes[13]
                        uid_len = payload_bytes[14]

                        if 15 + uid_len <= len(payload_bytes):
                            uid_bytes = payload_bytes[15 : 15 + uid_len]
                            result.hex_uid = " ".join(f"{b:02X}" for b in uid_bytes)
                            result.log_message += f"\n🔑 UID HARDWARE ESTRATTO: [{result.hex_uid}] (SAK: 0x{sak_byte:02X})"

                            # Matrice decisionale NXP AN10833 [NFC-2]
                            if sak_byte == 0x00:
                                result.tag_family = "NXP NTAG / MIFARE Ultralight"
                            elif sak_byte == 0x20:
                                result.tag_family = "ISO/IEC 14443-4 SmartCard (CIE / TS-CNS)"
                            elif sak_byte == 0x08:
                                result.tag_family = "MIFARE Classic 1K"
                            else:
                                result.tag_family = f"Tag ISO 14443A Alternativo (SAK: 0x{sak_byte:02X})"
                
                # Sotto-caso B: È una normale risposta APDU
                else:
                    result.event_type = "APDU"
                    result.log_message = f"◀️ RISPOSTA APDU CARTA: [{result.hex_payload}]"
                    
                    # Generazione della stringa ASCII filtrata per i soli caratteri stampabili (da 32 a 126)
                    ascii_chars = []
                    for b in payload_bytes:
                        if 32 <= b <= 126:
                            ascii_chars.append(chr(b))
                        else:
                            ascii_chars.append(".") # Carattere di riempimento per i byte non stampabili
                    
                    result.ascii_payload = "".join(ascii_chars)
                
                return result

            else:
                # Pacchetto troncato, aspetta altri dati
                return result

        # Byte non riconosciuto o rumore
        result.bytes_consumed = 1
        return result
