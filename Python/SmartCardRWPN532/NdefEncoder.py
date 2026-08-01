#**************************************************************************************#
# Nome Modulo: NdefEncoder.py
# Descrizione: Helper specifico per la compilazione e la formattazione binaria TLV NDEF.
#**************************************************************************************#

class NdefEncoder:
    @staticmethod
    def compile_records(records_data):
        """
        Prende una lista di dizionari del tipo: [{'type': 'T' o 'U', 'value': 'stringa'}]
        Genera l'array di byte completo racchiuso nel contenitore TLV (0x03 ... 0xFE).
        """
        ndef_payload = []
        total_records = len(records_data)
        
        if total_records == 0:
            return []

        for idx, rec in enumerate(records_data):
            rec_type = rec['type']   # "T" (Testo) o "U" (URI/URL)
            value_str = rec['value']
            
            # 1. COMPOSIZIONE PAYLOAD SPECIFICO DEL RECORD
            record_payload = []
            if rec_type == "U":
                # Semplificazione: Assumiamo il prefisso standard "https://www." (0x02)
                # Rimuoviamo il prefisso dalla stringa se l'utente lo ha inserito manualmente
                clean_value = value_str.replace("https://www.", "").replace("http://www.", "")
                record_payload.append(0x02) # Prefisso binario standard
                record_payload.extend([ord(c) for c in clean_value])
            elif rec_type == "T":
                # Standard Text: 1 byte status (lunghezza lingua = 2 per "en") + codice lingua + testo
                record_payload.append(0x02) # 0x02 significa: UTF-8, lunghezza codice lingua = 2
                record_payload.extend([ord('e'), ord('n')]) # Codice lingua fisso "en"
                record_payload.extend([ord(c) for c in value_str.encode('utf-8', errors='replace').decode('utf-8')])

            # 2. CALCOLO DEI BIT DI CONTROLLO DELL'HEADER NDEF (Flags Byte)
            mb = 1 if idx == 0 else 0                   # Message Begin (1 solo per il primo record)
            me = 1 if idx == (total_records - 1) else 0 # Message End (1 solo per l'ultimo record)
            cf = 0                                      # Chunk Flag (No chunking)
            sr = 1 if len(record_payload) <= 255 else 0 # Short Record (1 se payload <= 255 byte)
            il = 0                                      # ID Length Present (No ID)
            tnf = 0x01                                  # Type Name Format: NFC Forum Well-Known

            flags_byte = (mb << 7) | (me << 6) | (cf << 5) | (sr << 4) | (il << 3) | tnf
            
            # Assemblaggio intestazione record
            ndef_payload.append(flags_byte)
            ndef_payload.append(len(rec_type)) # Lunghezza del tipo (sempre 1 per "T" o "U")
            
            if sr == 1:
                ndef_payload.append(len(record_payload)) # 1 byte lunghezza payload
            else:
                p_len = len(record_payload)
                ndef_payload.extend([
                    (p_len >> 24) & 0xFF,
                    (p_len >> 16) & 0xFF,
                    (p_len >> 8) & 0xFF,
                    p_len & 0xFF
                ])
                
            ndef_payload.append(ord(rec_type)) # Inserimento del tipo ("T" o "U")
            ndef_payload.extend(record_payload) # Inserimento del payload reale

        # 3. INCAPSULAMENTO NEL BLOCCO CONTENITORE TLV (Type 0x03)
        tlv_frame = []
        tlv_frame.append(0x03) # Type: NDEF Message
        
        ndef_len = len(ndef_payload)
        if ndef_len <= 254:
            tlv_frame.append(ndef_len)
        else:
            tlv_frame.append(0xFF) # Indicatore di lunghezza estesa a 3 byte
            tlv_frame.append((ndef_len >> 8) & 0xFF)
            tlv_frame.append(ndef_len & 0xFF)
            
        tlv_frame.extend(ndef_payload)
        tlv_frame.append(0xFE) # Terminator TLV obbligatorio NFC Forum

        # 4. ALLINEAMENTO AL PADDING A PAGINE DA 4 BYTE
        while len(tlv_frame) % 4 != 0:
            tlv_frame.append(0x00) # Riempiamo l'ultima pagina incompleta con byte nulli

        return tlv_frame
