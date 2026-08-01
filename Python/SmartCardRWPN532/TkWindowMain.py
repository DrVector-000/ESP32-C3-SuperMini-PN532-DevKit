from tkinter import *
from tkinter import ttk
from tkinter import scrolledtext
from datetime import datetime
import SerialHelper
import SerialDevice
import time
from tkinter import filedialog
import CcidParser
import NdefParser

class TkWindowMain:

    # Private attributes
    serialdevice: SerialDevice
    portscb: ttk.Combobox
    text_area: scrolledtext.ScrolledText
    btndisconnect: ttk.Button
    btnconnect: ttk.Button
    root: Tk # Memorizziamo l'istanza root per gestire i cicli temporizzati .after()
    
    # Elementi aggiuntivi per Info Carta, Tab e Status
    status_label: ttk.Label
    card_status_val: ttk.Label
    card_type_val: ttk.Label
    card_uid_val: ttk.Label
    card_atr_val: ttk.Label


    # Costruttore
    def __init__(self):
        # Istanza oggetto SerialDeviceBase
        self.serialdevice = SerialDevice.SerialDevice(115200)
        self.__message_sequence = 0 
        
        # Variabili di stato per la catena di lettura NDEF asincrona
        self.__ndef_reading_active = False
        self.__ndef_current_page = 0
        self.__ndef_max_page = 39       # Limite standard per NTAG213 (pagine 4-39 utente)
        self.__ndef_raw_buffer = []      # Buffer lineare in cui accumulare i byte estratti


    # Metodi (accesso privato)
    def __SetControlsState(self, connect):
        if connect:
            self.btndisconnect['state'] = NORMAL
            self.btnconnect['state'] = DISABLED
            self.page_spinbox['state'] = 'normal'
            self.btn_read_page['state'] = 'normal'
            self.status_label['text'] = f"Seriale [{self.portscb.get()}] Connessa"
        else:
            self.btndisconnect['state'] = DISABLED
            self.btnconnect['state'] = NORMAL
            self.page_spinbox['state'] = 'disabled'
            self.btn_read_page['state'] = 'disabled'
            self.status_label['text'] = "Seriale Disconnessa"
            self.btn_read_ndef['state'] = 'disabled'
            
    def __Log(self, message):
        """Aggiunge una riga di testo alla console log con il timestamp esatto."""
        timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        self.text_area.insert(END, f"[{timestamp}] {message}\n")
        self.text_area.see(END) # Autoscroll automatico verso il basso

    def __UpdateLoop(self):
        """Ciclo di monitoraggio non bloccante che delega il parsing alla classe Helper."""
        if self.serialdevice.is_open():
            data = self.serialdevice.read_bytes()
            if data:
                packet = list(data)
                i = 0
                
                # Ciclo di consumo del buffer seriale tramite l'Helper statica
                while i < len(packet):
                    result = CcidParser.CcidParser.parse_stream(packet, start_index=i)
                    
                    # Se l'helper non ha consumato byte, significa che il pacchetto è troncato
                    if result.bytes_consumed == 0:
                        break
                        
                    # Applica le modifiche grafiche in base all'evento decodificato
                    if result.event_type == "SLOT_CHANGE":
                        if result.slot_status == 0x03:
                            self.card_status_val.config(text="Smartcard Rilevata", foreground="green")
                            self.__Log(result.log_message)
                            
                            # --- GENERAZIONE ED INVIO AUTOMATICO CCID ICCPOWERON (0x62) ---
                            self.__message_sequence = (self.__message_sequence + 1) & 0xFF
                            
                            # Struttura fissa dell'header CCID PC_to_RDR_IccPowerOn (10 byte):
                            # [0] 0x62, [1-4] Lunghezza payload (0), [5] Slot 0, [6] bSeq, [7] Power auto (0), [8-9] RFU
                            power_on_packet = [0x62, 0x00, 0x00, 0x00, 0x00, 0x00, self.__message_sequence, 0x00, 0x00, 0x00]
                            
                            self.__Log("▶️ INVIO CCID COMANDO: PC_to_RDR_IccPowerOn (0x62) per richiedere ATR...")
                            self.serialdevice.write_bytes(power_on_packet)
                            
                        elif result.slot_status == 0x02:
                            self.__ndef_reading_active = False # Forza lo stop se la carta viene tolta
                            self.card_status_val.config(text="Slot Vuoto", foreground="orange")
                            self.card_type_val.config(text="-")
                            self.card_uid_val.config(text="-")
                            self.card_atr_val.config(text="-")
                            self.raw_data_output.config(text="-")
                            self.btn_read_ndef['state'] = 'disabled'

                            # --- CANCELLAZIONE NODI DELLA TREEVIEW AL DISTACCO ---
                            for item in self.ndef_tree.get_children():
                                self.ndef_tree.delete(item)
                                
                            self.__Log(result.log_message)
                        
                    elif result.event_type == "ATR":
                        self.card_atr_val.config(text=result.hex_atr)
                        self.card_uid_val.config(text=result.hex_uid)
                        self.card_type_val.config(text=result.tag_family)
                        self.btn_read_ndef['state'] = 'normal'  # SBLOCCO: La carta è pronta per il dump NDEF
                        self.__Log(result.log_message)
                        
                    elif result.event_type == "APDU":
                        self.__Log(result.log_message)
                        
                        # -------------------------------------------------------------
                        # SCENARIO A: La lettura sequenziale NDEF è attiva
                        # -------------------------------------------------------------
                        if self.__ndef_reading_active:
                            # Trasformiamo la stringa esadecimale dell'helper in byte numerici interi
                            # (Escludendo gli ultimi 2 byte che rappresentano la Status Word 90 00)
                            raw_hex_list = result.hex_payload.split()
                            if len(raw_hex_list) >= 2 and raw_hex_list[-2:] == ["90", "00"]:
                                raw_hex_list = raw_hex_list[:-2]
                                
                            page_bytes = [int(hx, 16) for hx in raw_hex_list]
                            self.__ndef_raw_buffer.extend(page_bytes)
                            
                            # Avanza alla pagina successiva
                            self.__ndef_current_page += 1
                            
                            if self.__ndef_current_page <= self.__ndef_max_page:
                                # Pianifica la richiesta della pagina successiva con un micro-ritardo 
                                # per lasciare respirare l'I2C e la seriale (30ms)
                                self.root.after(30, self.__RequestNextNdefPage)
                            else:
                                # FINE DELLA CATENA: La memoria utente è stata interamente estratta!
                                self.__ndef_reading_active = False
                                self.btn_read_ndef['state'] = 'normal' # Riabilita il bottone
                                self.__Log("🏁 SCANSIONE COMPLETATA: Elaborazione record NDEF in corso...")
                                
                                # Invochiamo il nostro Helper NdefParser passando il buffer accumulato
                                detected_records = NdefParser.NdefParser.parse_ndef_message(self.__ndef_raw_buffer)
                                
                                if not detected_records:
                                    self.__Log("⚠️ ANALISI NDEF: Nessun record valido o formato TLV vuoto trovato.")
                                else:
                                    # Inseriamo i record estratti all'interno della Treeview grafica
                                    for rec in detected_records:
                                        self.ndef_tree.insert('', END, values=(
                                            rec.index,
                                            rec.type_str,
                                            rec.payload,
                                            rec.summary
                                        ))
                                        self.__Log(f"📝 Record #{rec.index} aggiunto alla tabella: {rec.summary}")
                        
                        # -------------------------------------------------------------
                        # SCENARIO B: Lettura manuale singola dal tab Raw (Nessun dump attivo)
                        # -------------------------------------------------------------
                        else:
                            formatted_output = f"{result.hex_payload}  ({result.ascii_payload})"
                            self.raw_data_output.config(text=formatted_output)
                        
                    i += result.bytes_consumed  # Avanza nel buffer dei byte consumati

            # Pianifica la riesecuzione asincrona del metodo dopo 100 millisecondi
            self.root.after(100, self.__UpdateLoop)

    # Funzioni eventi bottoni
    # Evento pressione bottone connetti
    def __Connect(self):
        port = self.portscb.get()
        self.serialdevice.setport(port)
        self.serialdevice.open()
        time.sleep(2)
        
        # Cancella stringhe di log
        self.text_area.delete(1.0, END)

        self.__SetControlsState(True)
        self.__Log(f"Connessione stabilita sulla porta {port}")
        
        # Avvia il loop di ascolto asincrono della presenza carta
        self.__UpdateLoop()

    # Evento pressione bottone disconnessione
    def __Disconnect(self):
        self.serialdevice.close()
        self.__SetControlsState(False)
        self.__Log("Connessione interrotta dall'utente.")

    def __ReadRawPage(self):
        """Invia il comando APDU standard PC/SC Read Binary verso l'ESP32."""
        page_index = self.target_page_var.get()
        self.__message_sequence = (self.__message_sequence + 1) & 0xFF
        
        # Struttura APDU PC/SC Read Binary: CLA=FF, INS=B0, P1=00, P2=Pagina, Le=04
        # Il firmware CCID racchiude questa APDU all'interno del frame PC_to_RDR_XfrBlock (0x6F)
        apdu_command = [0xFF, 0xB0, 0x00, page_index & 0xFF, 0x04]
        
        # Intestazione CCID fissa a 10 byte per XfrBlock (0x6F):
        # 0x6F, [1-4] Lunghezza APDU (5 bytes), Slot 0, bSeq, [7-9] RFU
        ccid_header = [0x6F, 0x05, 0x00, 0x00, 0x00, 0x00, self.__message_sequence, 0x00, 0x00, 0x00]
        full_packet = ccid_header + apdu_command
        
        self.__Log(f"▶️ INVIO APDU COMANDO (Read Page {page_index}): [FF B0 00 {page_index:02X} 04]")
        self.serialdevice.write_bytes(full_packet)

    def __ReadNdefSequence(self):
        """Innesca la sequenza di interrogazione e scaricamento dei blocchi NDEF."""
        self.__Log("🚀 AVVIO SCANSIONE: Inizio scaricamento sequenziale pagine NDEF...")
        
        # Pulisce la tabella prima di un nuovo caricamento dati
        for item in self.ndef_tree.get_children():
            self.ndef_tree.delete(item)
            
        # Inizializzazione dei parametri della macchina a stati
        self.__ndef_raw_buffer = []
        self.__ndef_current_page = 4
        self.__ndef_reading_active = True
        
        # Disabilita temporaneamente il bottone durante il dump per evitare richieste sovrapposte
        self.btn_read_ndef['state'] = 'disabled'
        
        # Richiede la prima pagina della catena
        self.__RequestNextNdefPage()

    def __RequestNextNdefPage(self):
        """Invia la richiesta APDU per la pagina corrente nella catena NDEF."""
        if not self.__ndef_reading_active:
            return
            
        self.__message_sequence = (self.__message_sequence + 1) & 0xFF
        apdu_command = [0xFF, 0xB0, 0x00, self.__ndef_current_page & 0xFF, 0x04]
        ccid_header = [0x6F, 0x05, 0x00, 0x00, 0x00, 0x00, self.__message_sequence, 0x00, 0x00, 0x00]
        full_packet = ccid_header + apdu_command
        
        # Invio sulla seriale
        self.serialdevice.write_bytes(full_packet)

    # Metodi (accesso pubblico)
    def Show(self):    
        # 1. CREAZIONE OBBLIGATORIA DELLA FINESTRA PRINCIPALE (Prima di ogni altra istanza Tk)
        self.root = Tk()
        self.root.title("SmartCard Read/Write PN532")
        self.root.geometry("850x800")
        self.root.eval('tk::PlaceWindow . center')

        # 2. ALLOCAZIONE VARIABILE DI CONTROLLO (Ora lo scope della root è valido al 100%)
        self.target_page_var = IntVar(value=4)

        # =====================================================================
        # 1. AREA CONNESSIONE SERIALE (Top Frame)
        # =====================================================================
        connframe = Frame(self.root)
        connframe.pack(expand=False, fill=X, anchor=NW, padx=10, pady=5)

        ttk.Label(connframe, text="Serial Port:").grid(column=1, row=1, sticky=W, padx=5, pady=5)

        # Lista porte seriali disponibili
        selports = StringVar()
        self.portscb = ttk.Combobox(connframe, textvariable=selports)
        self.portscb['values'] = SerialHelper.GetSerialPorts()
        self.portscb['state'] = 'readonly'
        self.portscb.grid(column=2, row=1, sticky=(W, E), padx=5, pady=5)

        # Bottoni connessione
        self.btnconnect = ttk.Button(connframe, text="Connect", command=self.__Connect)
        self.btnconnect.grid(column=3, row=1, sticky=W, padx=5, pady=5)
        self.btnconnect['state'] = NORMAL
        
        self.btndisconnect = ttk.Button(connframe, text="Disconnect", command=self.__Disconnect)
        self.btndisconnect.grid(column=4, row=1, sticky=W, padx=5, pady=5)
        self.btndisconnect['state'] = DISABLED

        # =====================================================================
        # 2. AREA PRESENZA CARTA E INFORMAZIONI (LabelFrame allineato ed elastico)
        # =====================================================================
        info_frame = ttk.LabelFrame(self.root, text=" Informazioni SmartCard / Tag ")
        info_frame.pack(expand=False, fill=X, anchor=NW, padx=10, pady=5)
        
        # CORREZIONE: Rendiamo elastica la colonna 4 della griglia (dove risiedono UID e ATR)
        # in modo che si allarghi dinamicamente seguendo la dimensione della finestra
        info_frame.columnconfigure(4, weight=1)
        
        ttk.Label(info_frame, text="Stato Slot:").grid(row=1, column=1, sticky=W, padx=10, pady=4)
        self.card_status_val = ttk.Label(info_frame, text="In attesa...", font=("Helvetica", 10, "bold"), foreground="orange")
        self.card_status_val.grid(row=1, column=2, sticky=W, padx=5, pady=4)
        
        ttk.Label(info_frame, text="Tipo Tag:").grid(row=2, column=1, sticky=W, padx=10, pady=4)
        self.card_type_val = ttk.Label(info_frame, text="-")
        self.card_type_val.grid(row=2, column=2, sticky=W, padx=5, pady=4)
        
        ttk.Label(info_frame, text="UID Hardware:").grid(row=1, column=3, sticky=W, padx=30, pady=4)
        self.card_uid_val = ttk.Label(info_frame, text="-", font=("Courier", 10, "bold"), foreground="blue")
        self.card_uid_val.grid(row=1, column=4, sticky=W, padx=5, pady=4)
        
        ttk.Label(info_frame, text="Stringa ATR:").grid(row=2, column=3, sticky=W, padx=30, pady=4)
        
        # CORREZIONE: sticky=W assicura che l'ATR parta da sinistra e si distenda orizzontalmente
        self.card_atr_val = ttk.Label(info_frame, text="-", font=("Courier", 10, "bold"), foreground="purple")
        self.card_atr_val.grid(row=2, column=4, sticky=W, padx=5, pady=4)

        # =====================================================================
        # 3. AREA STRUTTURA A SCHEDE / TAB
        # =====================================================================
        notebook = ttk.Notebook(self.root)
        notebook.pack(expand=False, fill=X, anchor=NW, padx=10, pady=5)
        
        tab_read = ttk.Frame(notebook)
        tab_write = ttk.Frame(notebook)
        tab_tools = ttk.Frame(notebook)
        
        notebook.add(tab_read, text=" Lettura (NDEF / Raw) ")
        notebook.add(tab_write, text=" Scrittura (NDEF / Raw) ")
        notebook.add(tab_tools, text=" Utility & Tools ")
        
        # --- Configurazione Grafica Tab Lettura Raw ---
        raw_read_frame = ttk.LabelFrame(tab_read, text=" Ispezione Memoria Grezza (Pagine / Blocchi) ")
        raw_read_frame.pack(fill=X, expand=True, padx=10, pady=10, anchor=NW)

        ttk.Label(raw_read_frame, text="Indice Pagina/Blocco Target:").grid(row=1, column=1, sticky=W, padx=10, pady=10)

        # Controllo Spinbox per selezionare la pagina (equivalente allo Stepper)
        self.page_spinbox = ttk.Spinbox(raw_read_frame, from_=0, to=255, width=5, textvariable=self.target_page_var)
        self.page_spinbox.grid(row=1, column=2, sticky=W, padx=5, pady=10)
        self.page_spinbox['state'] = 'disabled'  # Disabilitato di default finché non c'è connessione

        self.btn_read_page = ttk.Button(raw_read_frame, text="Leggi Pagina", command=self.__ReadRawPage)
        self.btn_read_page.grid(row=1, column=3, sticky=W, padx=15, pady=10)
        self.btn_read_page['state'] = 'disabled'  # Disabilitato di default

        ttk.Label(raw_read_frame, text="Buffer Contenuto Ricevuto:").grid(row=2, column=1, sticky=W, padx=10, pady=10)
        
        # Unica etichetta per Hex + ASCII esteso in orizzontale
        self.raw_data_output = ttk.Label(raw_read_frame, text="-", font=("Courier", 11, "bold"), foreground="blue")
        self.raw_data_output.grid(row=2, column=2, columnspan=3, sticky=W, padx=5, pady=10)

        # =====================================================================
        # --- Configurazione Grafica Tab Lettura NDEF (Tabella Record) ---
        # =====================================================================
        ndef_read_frame = ttk.LabelFrame(tab_read, text=" Record Messaggio NDEF Rilevati ")
        ndef_read_frame.pack(fill=BOTH, expand=True, padx=10, pady=10, anchor=NW)

        # --- BARRA DI COMANDO SUPERIORE PER LETTURA NDEF ---
        ndef_action_bar = ttk.Frame(ndef_read_frame)
        ndef_action_bar.pack(fill=X, expand=False, padx=5, pady=5)

        self.btn_read_ndef = ttk.Button(ndef_action_bar, text="Scansiona Record NDEF", command=self.__ReadNdefSequence)
        self.btn_read_ndef.pack(side=LEFT, padx=5, pady=2)
        self.btn_read_ndef['state'] = 'disabled'  # Disabilitato di default

        # Creazione dei canali di colonna per la Treeview
        columns = ('index', 'type', 'payload', 'summary')
        self.ndef_tree = ttk.Treeview(ndef_read_frame, columns=columns, show='headings', selectmode='browse')

        # Definizione delle intestazioni delle colonne
        self.ndef_tree.heading('index', text="Rec. #")
        self.ndef_tree.heading('type', text="Tipo Record")
        self.ndef_tree.heading('payload', text="Payload (Hex)")
        self.ndef_tree.heading('summary', text="Contenuto Interpretato")

        # Configurazione delle geometrie e dei pesi delle colonne (orizzontale)
        self.ndef_tree.column('index', width=60, anchor=CENTER, minwidth=50)
        self.ndef_tree.column('type', width=100, anchor=CENTER, minwidth=80)
        self.ndef_tree.column('payload', width=220, anchor=W, minwidth=150)
        self.ndef_tree.column('summary', width=400, anchor=W, minwidth=250)

        # Inserimento della Scrollbar verticale accoppiata alla tabella
        tree_scroll = ttk.Scrollbar(ndef_read_frame, orient=VERTICAL, command=self.ndef_tree.yview)
        self.ndef_tree.configure(yscrollcommand=tree_scroll.set)

        # Posizionamento dei widget tramite pack combinato per occupare l'area elastica
        tree_scroll.pack(side=RIGHT, fill=Y)
        self.ndef_tree.pack(side=LEFT, fill=BOTH, expand=True)


        ttk.Label(tab_write, text="Campi di compilazione per il flash dei blocchi.").pack(padx=10, pady=10)
        ttk.Label(tab_tools, text="Funzioni di Wipe memoria e formattazione TLV.").pack(padx=10, pady=10)

        # =====================================================================
        # 4. AREA LOG
        # =====================================================================
        self.textframe = Frame(self.root)
        self.textframe.pack(expand=True, fill=BOTH, anchor=NW, padx=10, pady=5)

        ttk.Label(self.textframe, text="Console di Diagnostica Transazioni APDU:", font=("Helvetica", 9, "bold")).pack(anchor=W, pady=2)
        self.text_area = scrolledtext.ScrolledText(self.textframe, wrap=WORD, width=50, height=8, font=("Courier", 10))
        self.text_area.pack(fill=BOTH, expand=True, anchor=CENTER)       

        # =====================================================================
        # 5. BARRA DI STATO
        # =====================================================================
        statusbar = ttk.Frame(self.root, relief=SUNKEN, padding=(2, 2))
        statusbar.pack(side=BOTTOM, fill=X)
        
        self.status_label = ttk.Label(statusbar, text="Seriale Disconnessa")
        self.status_label.pack(side=LEFT, padx=5)

        self.root.mainloop()
