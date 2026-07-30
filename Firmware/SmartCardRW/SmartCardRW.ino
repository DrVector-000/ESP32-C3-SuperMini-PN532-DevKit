//********************************************************************************************************//
// Nome Modulo: SmartCardRW.ino
// Descrizione: Programma principale per la gestione del lettore/scrittore di smartcard PN532.
//              Configurato con Interrupt Hardware (FALLING) ed Heartbeat a 1 secondo per il distacco.
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
// Variabili globali e Bandierine Hardware Volatili
//********************************************************************************************************//
Adafruit_PN532 nfcDevice(PN532_IRQ, PN532_RESET); 
bool _pn532Ok = false;
bool cardPresent = false;

// Bandierina asincrona gestita dalla ISR hardware
volatile bool cardInsertedPending = false;

// Variabili per il controllo temporizzato del distacco (1 secondo)
unsigned long lastRemovalCheckTime = 0;
const unsigned long removalCheckInterval = 1000; // Intervallo di 1000 millisecondi (1 secondo)

extern uint8_t pn532_packetbuffer[]; 

void sendNotifySlotChange(uint8_t status);

// ============================================================================
// FUNZIONE DI INTERRUPT (ISR) - FALLING MODE STATICO
// ============================================================================
void IRAM_ATTR handlePscInterrupt() {
  cardInsertedPending = true;
}

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

void loop() {
  if (_pn532Ok)
  {
    unsigned long currentTime = millis();
    int irqCurr = digitalRead(PN532_IRQ);

    // --- 1. GESTIONE INSERIMENTO (Asincrono guidato dall'Interrupt hardware) ---
    if (cardInsertedPending) {
      cardInsertedPending = false; // Consuma immediatamente l'evento
      
      if (!cardPresent) {
        uint8_t uid[12]; // Allocazione ad array sicura per lo stack RAM
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
          
          sendNotifySlotChange(0x03); // Invia lo stato "Presente" (0x03) a SwiftUI
          nfcDevice.inListPassiveTarget(); // Mantiene l'aggancio logico originario del chip
          
          lastRemovalCheckTime = currentTime; // Sincronizza il timer di partenza
        }
      }
    }

    // --- 2. GESTIONE RIMOZIONE CARTA TEMPORIZZATA (Eseguita ogni secondo) ---
    if (cardPresent) {
      // Verifica se è passato almeno 1 secondo dall'ultimo controllo RF
      if (currentTime - lastRemovalCheckTime >= removalCheckInterval) {
        lastRemovalCheckTime = currentTime; // Aggiorna il timestamp dell'ultimo controllo
        
        // Esegue il controllo originale stabile: se il pin è HIGH e la carta non risponde più
        if (irqCurr == HIGH && !nfcDevice.inListPassiveTarget()) {
          cardPresent = false;
          buzzerPlayCardRemoved(); // Doppio beep istantaneo eseguito solo al distacco reale
          
          // Pulisce lo stato locale nel parser e notifica SwiftUI (0x02 = Slot Vuoto)
          ccidUpdateCurrentUid(NULL, 0, 0x00); 
          sendNotifySlotChange(0x02); 
        }
      }
    }

    // --- 3. PASSAMANO SERIALE PC/SC DA MACOS ---
    while (Serial.available() > 0) {
      ccidParseByte(Serial.read());
    }

    delay(10);
  }
}

void sendNotifySlotChange(uint8_t status) {
  ccidSendNotifySlotChange(status);
}
