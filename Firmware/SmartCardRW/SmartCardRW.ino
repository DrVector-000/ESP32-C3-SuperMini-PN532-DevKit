//********************************************************************************************************//
// Nome Modulo: SmartCardRW.ino
// Descrizione: Programma principale per la gestione del lettore/scrittore di smartcard PN532.
//              Configurato con Interrupt Hardware su fronte di discesa (FALLING) e ciclo a 1 secondo per 
//              verificare la rimozione.
//********************************************************************************************************//

#include <Arduino.h>
#include "Adafruit_PN532.h" 
#include "BuzzerManager.h"
#include "CcidParser.h" 
#include "CcidTransmitter.h" 

//********************************************************************************************************//
// Costanti globali
//********************************************************************************************************//
#define SDA_PIN       8
#define SCL_PIN       9
#define PN532_IRQ     10
#define PN532_RESET   1

//********************************************************************************************************//
// Variabili globali e Flags Hardware Volatili
//********************************************************************************************************//
Adafruit_PN532 nfcDevice(PN532_IRQ, PN532_RESET); 
bool _pn532Ok = false;
bool cardPresent = false;

// Flag asincrona gestita dalla ISR hardware
volatile bool cardInsertedPending = false;

// Variabili per il controllo temporizzato della rimozione (1 secondo)
unsigned long lastRemovalCheckTime = 0;
const unsigned long removalCheckInterval = 1000; // Intervallo di 1000 millisecondi (1 secondo)

extern uint8_t pn532_packetbuffer[]; 

void sendNotifySlotChange(uint8_t status);

// ============================================================================
// Funzione di Interrupt (ISR) - Falling Mode (Fronte di discesa)
// ============================================================================
void IRAM_ATTR handlePscInterrupt() {
  cardInsertedPending = true;
}

// ============================================================================
// Setup
// ============================================================================
void setup() {
  Serial.begin(115200);
  delay(1000);

  buzzerInit();

  Serial.println("");
  Serial.println("*** ESP32-C3 SUPERMINI PN532 DEVKIT v1.00 ***");
  Serial.println("");

  nfcDevice.begin();

  uint32_t versiondata = nfcDevice.getFirmwareVersion();
  if (!versiondata)
  {
    Serial.print("Nessuna scheda PN53x trovata");
    buzzerPlayErrorTone();
  }
  else
  {
    // Configurazione del pin IRQ in modalità ingresso con pull-up standard
    pinMode(PN532_IRQ, INPUT_PULLUP);
    
    // Aggancio statico dell'interrupt hardware sul fronte di discesa (FALLING)
    attachInterrupt(digitalPinToInterrupt(PN532_IRQ), handlePscInterrupt, FALLING);

    // Mette il chip in modalità ascolto iniziale
    nfcDevice.startPassiveTargetIDDetection(PN532_MIFARE_ISO14443A);

    _pn532Ok = true;
    Serial.println("Inizializzazione completa.");
    Serial.println("");
    
    buzzerPlayBootTone();
  }
}

// ============================================================================
// Main Loop
// ============================================================================
void loop() {
  if (_pn532Ok)
  {
    unsigned long currentTime = millis();
    int irqCurr = digitalRead(PN532_IRQ);

    // --- 1. Gestione inserimento della carta (Asincrono guidato dall'Interrupt hardware) ---
    if (cardInsertedPending) {
      cardInsertedPending = false; // Consuma immediatamente l'evento
      
      if (!cardPresent) {
        uint8_t uid[12];
        uint8_t uidLen = 0;
        uint8_t hardwareSak = 0x00;
        memset(uid, 0, sizeof(uid));
        
        // Utilizziamo la funzione ad alto livello che estrae l'UID e popola il buffer
        if (nfcDevice.readDetectedPassiveTargetID(uid, &uidLen)) {
          cardPresent = true;
          buzzerPlayCardInserted(); // Singolo beep pulito all'inserimento
          
          // Estrazione nativa dell'esatto SAK hardware memorizzato all'indice 11 del buffer
          hardwareSak = pn532_packetbuffer[11];
          ccidUpdateCurrentUid(uid, uidLen, hardwareSak);
          
          sendNotifySlotChange(0x03); // Invia lo stato "Presente" (0x03)
          //nfcDevice.inListPassiveTarget(); // Mantiene l'aggancio logico originario del chip
          
          lastRemovalCheckTime = currentTime; // Sincronizza il timer di partenza
        }
      }
    }

    // --- 2. Gestione rimozione della carta (Eseguita ogni secondo) ---
    if (cardPresent && (currentTime - lastRemovalCheckTime >= removalCheckInterval)) {
      lastRemovalCheckTime = currentTime;
      
      // ============================================================================
      // LOG DI CONTROLLO HARDWARE: Stampa il SAK in formato Esadecimale (HEX)
      // ============================================================================
      //Serial.print("DEBUG SAK HARDWARE RILEVATO: 0x");
      //if (current_tag_sak < 0x10) Serial.print("0"); // Inserisce lo zero iniziale se il valore è a una sola cifra (es. 0x08)
      //Serial.println(current_tag_sak, HEX);
      // ============================================================================
      
      // Carte ISO14443-4 (Layer 4)
      if (current_tag_sak == 0x20) {
        if (!checkCardPresence()) {
          cardPresent = false;
          buzzerPlayCardRemoved(); 
          
          ccidUpdateCurrentUid(NULL, 0, 0x00); 
          sendNotifySlotChange(0x02); 

          // Mette il chip in modalità ascolto iniziale
          nfcDevice.startPassiveTargetIDDetection(PN532_MIFARE_ISO14443A);
        }
      }
      // Carte ISO14443-3 (Layer 3)
      else {
        if (!nfcDevice.inListPassiveTarget()) {
          cardPresent = false;
          buzzerPlayCardRemoved(); 
          
          ccidUpdateCurrentUid(NULL, 0, 0x00); 
          sendNotifySlotChange(0x02); 
        }
      }
    }

    // --- 3. Gestione pacchetti dalla seriale PC/SC ---
    while (Serial.available() > 0) {
      ccidParseByte(Serial.read());
    }

    delay(10);
  }
}

// ============================================================================
// Notifica modifica nello slot
// ============================================================================
void sendNotifySlotChange(uint8_t status) {
  ccidSendNotifySlotChange(status);
}

// ============================================================================
// Verifica presenza carta layer 4
// ============================================================================
bool checkCardPresence() {
  // APDU vuota di test (4 byte)
  uint8_t apduPresence[] = {0x00, 0x00, 0x00, 0x00}; 
  
  uint8_t response[20];
  uint8_t responseLength = sizeof(response);

  // Esegue l'invio dell'APDU alla carta attiva
  bool success = nfcDevice.inDataExchange(apduPresence, sizeof(apduPresence), response, &responseLength);

  if (success) {
    // La carta ha risposto (es. errore 6E 00 o 6D 00), quindi è PRESENTE
    //Serial.print("Carta Presente. Risposta Layer 4: ");
    //for (uint8_t i = 0; i < responseLength; i++) {
    //  Serial.print(response[i], HEX);
    //  Serial.print(" ");
    //}
    //Serial.println();
    return true;
  } else {
    // Il PN532 è andato in timeout (Nessuna risposta fisica dalla carta)
    //Serial.println("CARTA RIMOSSA o Timeout di comunicazione.");
    return false;
  }
}