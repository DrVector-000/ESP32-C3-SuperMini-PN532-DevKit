#**************************************************************************************#
# Nome Modulo: NdefParser.py
# Descrizione: Helper specifico per il parsing, l'estrazione e la decodifica dei record NDEF.
#**************************************************************************************#

class NdefRecordModel:
    """Rappresenta un singolo record NDEF decodificato con i suoi metadati."""
    def __init__(self, record_index, tnf, record_type, payload_content, summary):
        self.index = record_index          # Indice progressivo del record nel messaggio
        self.tnf = tnf                      # Type Name Modifier (es. 0x01 = NFC Forum Well-Known)
        self.type_str = record_type         # Stringa del tipo (es. "T" per Text, "U" per URI)
        self.payload = payload_content       # Contenuto grezzo o parziale del payload
        self.summary = summary               # Descrizione testuale leggibile del record (es. "URL: https://...")

class NdefParser:
    @staticmethod
    def parse_ndef_message(raw_bytes):
        """
        Analizza un array di byte grezzi alla ricerca del blocco TLV NDEF (0x03).
        Esegue il parsing di tutti i record interni e restituisce una lista di NdefRecordModel.
        """
        records_list = []
        if not raw_bytes or len(raw_bytes) < 4:
            return records_list

        # --- FASE 1: NAVIGAZIONE ED ESTRAZIONE DEL PAYLOAD NDEF DAL CONTENITORE TLV ---
        i = 0
        ndef_payload = None
        
        while i < len(raw_bytes):
            tlv_type = raw_bytes[i]
            
            if tlv_type == 0x00: # NULL TLV (Padding), avanza
                i += 1
                continue
            elif tlv_type == 0x03: # NDEF Message TLV trovato!
                if i + 1 >= len(raw_bytes):
                    break
                
                tlv_len = raw_bytes[i + 1]
                if tlv_len == 0xFF: # Lunghezza estesa a 3 byte (opzionale nei tag grandi)
                    if i + 3 >= len(raw_bytes):
                        break
                    tlv_len = (raw_bytes[i + 2] << 8) | raw_bytes[i + 3]
                    start_index = i + 4
                else:
                    start_index = i + 2
                
                # Ritagliamo l'array contenente solo il messaggio NDEF puro
                if start_index + tlv_len <= len(raw_bytes):
                    ndef_payload = raw_bytes[start_index : start_index + tlv_len]
                break
            elif tlv_type == 0xFE: # Terminator TLV, la scansione si interrompe
                break
            else:
                # Altri tipi di TLV (es. Proprietary 0xFD), salta in base alla lunghezza
                if i + 1 < len(raw_bytes):
                    i += 2 + raw_bytes[i + 1]
                else:
                    break

        if not ndef_payload:
            return records_list

        # --- FASE 2: DECODIFICA DEI SINGOLI RECORD NDEF ---
        ptr = 0
        record_idx = 1
        
        while ptr < len(ndef_payload):
            header = ndef_payload[ptr]
            
            # Estrazione dei bit di controllo dall'header del record
            mb = (header & 0x80) >> 7  # Message Begin
            me = (header & 0x40) >> 6  # Message End
            cf = (header & 0x20) >> 5  # Chunk Flag
            sr = (header & 0x10) >> 4  # Short Record (se 1, la lunghezza payload è 1 byte)
            il = (header & 0x08) >> 3  # ID Length Present
            tnf = header & 0x07        # Type Name Format
            
            ptr += 1
            if ptr >= len(ndef_payload): break
            
            type_len = ndef_payload[ptr]
            ptr += 1
            if ptr >= len(ndef_payload): break
            
            # Estrazione lunghezza del payload (1 byte se SR=1, altrimenti 4 byte)
            if sr == 1:
                payload_len = ndef_payload[ptr]
                ptr += 1
            else:
                if ptr + 3 >= len(ndef_payload): break
                payload_len = (ndef_payload[ptr] << 24) | (ndef_payload[ptr+1] << 16) | (ndef_payload[ptr+2] << 8) | ndef_payload[ptr+3]
                ptr += 4
                
            id_len = 0
            if il == 1:
                if ptr >= len(ndef_payload): break
                id_len = ndef_payload[ptr]
                ptr += 1
                
            # Estrazione del tipo di Record
            if ptr + type_len > len(ndef_payload): break
            type_bytes = ndef_payload[ptr : ptr + type_len]
            type_str = "".join(chr(b) for b in type_bytes)
            ptr += type_len
            
            # Salta i byte dell'ID se presenti
            if id_len > 0:
                ptr += id_len
                if ptr > len(ndef_payload): break
                
            # Estrazione del payload effettivo del record
            if ptr + payload_len > len(ndef_payload): break
            record_payload = ndef_payload[ptr : ptr + payload_len]
            ptr += payload_len
            
            # --- FASE 3: INTERPRETAZIONE DEI TIPI WELL-KNOWN (TEXT & URI) ---
            summary = "Record non riconosciuto o proprietario"
            
            if tnf == 0x01: # Well-Known Type
                if type_str == "U" and len(record_payload) > 1:
                    # Tabella dei prefissi URI standard NFC Forum
                    prefixes = {
                        0x01: "http://www.", 0x02: "https://www.", 0x03: "http://", 0x04: "https://",
                        0x05: "tel:", 0x06: "mailto:", 0x0D: "ftp://anonymous:anonymous@", 0x1C: "btspp://"
                    }
                    prefix_code = record_payload[0]
                    uri_prefix = prefixes.get(prefix_code, "")
                    uri_body = "".join(chr(b) for b in record_payload[1:] if 32 <= b <= 126)
                    summary = f"Link/URI: {uri_prefix}{uri_body}"
                    
                elif type_str == "T" and len(record_payload) > 0:
                    status_byte = record_payload[0]
                    lang_code_len = status_byte & 0x3F # Lunghezza del codice lingua (es. "en", "it")
                    if 1 + lang_code_len < len(record_payload):
                        # Il testo reale si trova dopo il codice lingua
                        text_bytes = record_payload[1 + lang_code_len :]
                        # Decodifichiamo provando UTF-8, saltando i caratteri non stampabili in fallback
                        try:
                            text_str = bytes(text_bytes).decode('utf-8', errors='replace')
                        except:
                            text_str = "".join(chr(b) for b in text_bytes if 32 <= b <= 126)
                        summary = f"Testo: {text_str}"
            
            # Creazione del modello ed inserimento nella lista dei risultati
            rec_model = NdefRecordModel(
                record_index=record_idx,
                tnf=tnf,
                record_type=type_str,
                payload_content=" ".join(f"{b:02X}" for b in record_payload),
                summary=summary
            )
            records_list.append(rec_model)
            record_idx += 1
            
        return records_list
