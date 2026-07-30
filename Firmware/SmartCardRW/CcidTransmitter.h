//********************************************************************************************************//
// Nome Modulo: CcidTransmitter.h
// Descrizione: Libreria per la formattazione, l'assemblaggio e l'invio dei pacchetti PC/SC CCID verso l'host.
//********************************************************************************************************//

#ifndef CCID_TRANSMITTER_H
#define CCID_TRANSMITTER_H

#include <Arduino.h>

#define RDR_TO_PC_NOTIFYSLOTCHANGE 0x50
#define RDR_TO_PC_DATABLOCK        0x80

/**
 * Trasmissione del pacchetto di notifica variazione stato dello slot
 */
inline void ccidSendNotifySlotChange(uint8_t status) {
  uint8_t packet[2]; // Allocazione ad array di 2 byte per consentire il passaggio del puntatore a Serial.write
  packet[0] = RDR_TO_PC_NOTIFYSLOTCHANGE;   
  packet[1] = status; 
  Serial.write(packet, 2);
}

/**
 * Assemblaggio dell'header a 10 byte e trasmissione del blocco dati verso l'host
 */
inline void ccidSendDataBlock(uint8_t seq, uint8_t* payloadData, uint32_t payloadLen) {
  uint8_t header[10]; // Allocazione ad array di 10 byte per l'header fisso CCID
  memset(header, 0, sizeof(header));
  
  header[0] = RDR_TO_PC_DATABLOCK; 
  header[1] = (uint8_t)(payloadLen & 0xFF);
  header[2] = (uint8_t)((payloadLen >> 8) & 0xFF);
  header[3] = (uint8_t)((payloadLen >> 16) & 0xFF);
  header[4] = (uint8_t)((payloadLen >> 24) & 0xFF);
  header[5] = 0x00; // bSlot (Slot 0)
  header[6] = seq;  // bSeq (Sequence Number)
  header[7] = 0x00; // bStatus (Nessun errore)
  header[8] = 0x00; // bError (Nessun errore)
  header[9] = 0x00; // bProtocolNum / RFU
  
  Serial.write(header, 10);
  if (payloadLen > 0 && payloadData != NULL) {
    Serial.write(payloadData, payloadLen);
  }
}

/**
 * Costruzione e invio dell'ATR dinamico standard PC/SC (Conforme Part 3)
 */
inline void ccidSendStandardAtrResponse(uint8_t seq, uint8_t* uidData, uint8_t uidLen, uint8_t sak) {
  uint8_t atrBuffer[32]; // Allocazione statica protetta
  memset(atrBuffer, 0, sizeof(atrBuffer));

  atrBuffer[0] = 0x3B; // Initial Header
  atrBuffer[1] = 0x80 + 7 + uidLen; // T0: 7 byte fissi PC/SC + i byte dell'UID
  atrBuffer[2] = 0x80; // T1
  atrBuffer[3] = 0x01; // Protocollo generico
  atrBuffer[4] = 0x80; 
  atrBuffer[5] = 0x4F; // App Category: PC/SC Workgroup
  atrBuffer[6] = 5 + uidLen; // Lunghezza dei byte storici contactless
  
  // RID Standard PC/SC (A0 00 00 03 06)
  atrBuffer[7] = 0xA0; 
  atrBuffer[8] = 0x00;
  atrBuffer[9] = 0x00;
  atrBuffer[10] = 0x03;
  atrBuffer[11] = 0x06; 
  
  atrBuffer[12] = 0x03;   // Standard Contactless Card Type (ISO 14443A)
  atrBuffer[13] = sak;    // Iniezione del vero SAK hardware
  atrBuffer[14] = uidLen; // Lunghezza dell'UID
  
  // Iniezione dei byte dell'UID hardware
  for (uint8_t i = 0; i < uidLen; i++) {
    atrBuffer[15 + i] = uidData[i];
  }
  
  // Calcolo del Checksum TCK finale
  uint8_t totalAtrLen = 15 + uidLen;
  uint8_t tck = 0;
  for (uint8_t i = 1; i < totalAtrLen; i++) {
    tck ^= atrBuffer[i];
  }
  atrBuffer[totalAtrLen] = tck;
  uint8_t finalPacketLen = totalAtrLen + 1;

  ccidSendDataBlock(seq, atrBuffer, finalPacketLen);
}

inline void ccidSendApduResponse(uint8_t seq, uint8_t* responseData, uint32_t responseLen) {
  ccidSendDataBlock(seq, responseData, responseLen);
}

#endif // CCID_TRANSMITTER_H
