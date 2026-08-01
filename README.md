# ESP32-C3-SuperMini-PN532-DevKit

![Platform](https://img.shields.io/badge/Platform-ESP32%20C3%20SuperMini-red?style=flat)
![IC Module](https://img.shields.io/badge/CI%20Module-PN532-brightgreen?style=flat)


Kit di Sviluppo per Lettore/Scrittore di SmartCard PC/SC con ESP32-C3 SuperMini e PN532.

Questo progetto realizza un ponte di comunicazione contactless ad alta stabilità basato sulle specifiche industriali **PC/SC Part 3** e sullo standard **CCID**. Il sistema è composto da un firmware ottimizzato per il microcontrollore RISC-V **ESP32-C3** e da un'applicazione nativa per **macOS** sviluppata in Swift/SwiftUI che centralizza l'intelligenza di analisi, la decodifica multi-record NDEF e il tracciamento diagnostico.

---

### 🛠️ Hardware di Riferimento
Il firmware e l'ingegnerizzazione di questo software sono stati scritti e collaudati espressamente per la scheda di sviluppo integrata disponibile su eBay:
👉 **[Scheda di Sviluppo ESP32-C3 SuperMini + PN532 su eBay](https://www.ebay.it/itm/127865020402)**

---

## 🚀 Caratteristiche Principali

### 📡 Firmware & Hardware (ESP32-C3)
* **True Hardware SAK Extraction:** Accesso diretto tramite *Pointer Casting* alla RAM del chip PN532 (`pn532_packetbuffer[11]`) per catturare il vero byte SAK (SEL_RES).
* **1-Second Heartbeat Polling:** Gestione della rimozione ad intervallo temporizzato (1000ms), compatibile con smartcard di tipo layer 3 che layer 4.
* **Feedback Acustici Dedicati:** Modulo PWM (`ledc`) integrato per generare notifiche sonore istantanee e differenziate all'inserimento, distacco o errore hardware.
* **Pure Pass-Through:** Il firmware non interpreta i comandi; inoltra in modo trasparente i blocchi APDU (`Update Binary`, `Read Binary`, `Get Data`) scambiati con l'host.

### 🍏 Software Applicativo (macOS)
* **Architettura Modulare SwiftUI:** Interfaccia nativa de-clutterizzata e suddivisa in schede indipendenti (`RawInspector`, `NdefReader`, `NdefWriter`) sfruttando la macro `@Observable`.
* **Analisi NXP AN10833 Estesa:** Switch decisionale rigoroso basato sulla combinazione di SAK hardware e lunghezza dell'UID per identificare all'istante l'IC esatto (NTAG, Mifare Classic 1K/4K, Mini, DESFire, Plus, o CNS/CIE/EMV).
* **Compilatore Multi-Record NDEF:** 
  * *Reader:* Scansione sequenziale delle pagine utente (4-39) con parsing ciclico della catena dei record (Well-Known Text "T" e URI/URL "U" con relativi prefissi).
  * *Writer:* Generazione automatica del payload binario TLV allineato a blocchi di 4 byte, con calcolo dinamico dei bit di controllo dell'header (`MB`/`ME` per record multipli).
* **Console di Diagnostica Transazioni:** Terminale grafico monospaziato in tempo reale che traccia i vettori esadecimali in ingresso (📥/◀️) e in uscita (▶️/💎). Include il supporto nativo `.textSelection(.enabled)` per consentire la copia dei byte via `Cmd+C`.

---

## 🔌 Schema di Collegamento Hardware

Il chip PN532 è interfacciato sul bus I2C dell'ESP32-C3 SuperMini. Il monitoraggio degli eventi è delegato a una linea di interrupt hardware.

| ESP32-C3 SuperMini Pin | Periferica / Componente | Descrizione |
| :--- | :--- | :--- |
| **GPIO 8** | PN532 SDA | Linea dati Bus I2C |
| **GPIO 9** | PN532 SCL | Linea clock Bus I2C |
| **GPIO 10** | PN532 IRQ | Notifica Interrupt Hardware (Open-Drain) |
| **GPIO 1** | PN532 RST | Linea di Reset (Collegata, non pilotata) |
| **GPIO 0** | BUZZER VCC (+) | Segnale acustico PWM (LEDC) |
| **GND** | GND (Comune) | Riferimento di massa negativo |
| **3V3** | VCC (+3.3V) | Alimentazione moduli |

---

## 📂 Struttura del Progetto

```text
├── SmartCardRW/                      # CODICE FIRMWARE (Arduino IDE)
│   ├── SmartCardRW.ino               # Loop principale e macchina a stati finiti (IRQ)
│   ├── BuzzerManager.h               # Driver audio PWM (ledc) e toni acustici
│   ├── CcidParser.h                  # Parser degli header CCID a 10 byte e smistatore APDU
│   └── CcidTransmitter.h             # Generatore di pacchetti RDR_to_PC ed ATR dinamici
│
└── ESP32_PN532_SmartCardReader/       # SOFTWARE MAC (Xcode / Swift)
    ├── SerialEnumerator.swift        # Servizio IOKit per l'enumerazione delle porte BSD
    ├── SerialCCIDEngine.swift        # Thread POSIX asincrono per l'I/O Raw della seriale
    ├── NDEFParser.swift              # Analizzatore e decodificatore di messaggi multi-record
    ├── NDEFEncoder.swift              # Compilatore e formattatore di flussi binari TLV NDEF
    ├── ReaderViewModel.swift         # ViewModel osservabile di stato e logica AN10833
    ├── ContentView.swift             # Layout principale a due colonne e TabView
    └── SubViews.swift                # Componenti isolati (Sidebar, LED, LogConsoleView)
```

---

## 🛠️ Istruzioni per l'Installazione e l'Uso

### 1. Flash del Firmware (ESP32-C3)
1. Apri l'Arduino IDE e installa la libreria ufficiale **Adafruit_PN532**.
2. Assicurati di aver installato il core ESP32 (versione 2.x o successive).
3. Seleziona come scheda `ESP32C3 Dev Module` (o affine).
4. Scollega temporaneamente il modulo dal Mac, ricollegalo e lancia l'Upload. Al termine dell'operazione, il lettore emetterà un singolo bip brillante di avvenuto boot.

### 2. Compilazione dell'App macOS
1. Apri la cartella del progetto Xcode sul tuo Mac.
2. Assicurati che il target sia configurato per macOS (richiede macOS 14+ Sonoma o versioni successive per il supporto della macro `@Observable`).
3. Premi **`Cmd + R`** per compilare ed eseguire l'applicazione nativa.

### 3. Workflow Operativo
1. Nella Sidebar dell'applicazione, seleziona la porta BSD associata all'ESP32-C3 (es. `/dev/cu.usbmodem...`) e clicca su **Connetti**.
2. Appoggia un tag (NTAG o una Carta d'Identità Elettronica / CIE): il lettore emetterà un beep, lo slot passerà a verde e la scheda **Raw Inspector** visualizzerà l'ATR esadecimale reale, l'UID e l'IC estratto.
3. Muoviti tra i tab **NDEF Reader** per scaricare e isolare in tessere colorate tutti i record memorizzati, oppure **NDEF Writer** per comporre una lista multi-campo personalizzata e flasharla sul tag in un solo clic.
4. Sfrutta la **Console di Diagnostica** in basso per selezionare con il mouse e copiare i byte delle transazioni APDU in caso di debug.

---

## 📄 Licenza

Questo progetto è rilasciato sotto la licenza **Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International** (CC BY-NC-SA 4.0).

![License](https://img.shields.io/badge/License-Creative%20Commons-green?style=flat)

*   **Libero utilizzo privato, didattico e di studio.**
*   **Vietata qualsiasi forma di commercializzazione** (vendita dell'hardware, dell'applicazione, o di derivati) senza l'esplicito consenso scritto dell'autore originale.
*   Ogni opera derivata o modifica deve essere ridistribuita mantenendo la medesima licenza e citando la paternità del progetto originale.
