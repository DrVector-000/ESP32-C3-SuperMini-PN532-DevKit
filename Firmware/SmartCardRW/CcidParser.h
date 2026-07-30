//********************************************************************************************************//
// Nome Modulo: CcidParser.h
// Descrizione: Libreria per il parsing, la decodifica e la gestione dei messaggi del protocollo PC/SC CCID.
//              Gestisce i comandi APDU Get Data, Pass-Through, Read Binary e Update Binary.
//********************************************************************************************************//

#ifndef CCID_PARSER_H
#define CCID_PARSER_H

#include <Arduino.h>
#include "Adafruit_PN532.h"
#include "CcidTransmitter.h" 

extern Adafruit_PN532 nfcDevice;

#define PC_TO_RDR_ICCPOWERON  0x62
#define PC_TO_RDR_XFRBLOCK    0x6F

#define CCID_BUFFER_SIZE      260
static uint8_t rx_buffer[CCID_BUFFER_SIZE];
static uint16_t rx_index = 0;

static uint8_t current_tag_uid[12];
static uint8_t current_tag_uid_len = 0;
static uint8_t current_tag_sak = 0x00;

inline void ccidUpdateCurrentUid(uint8_t* uid, uint8_t len, uint8_t sak) {
  current_tag_uid_len = len;
  current_tag_sak = sak;
  if (len > 0 && uid != NULL) {
    memcpy(current_tag_uid, uid, len);
  } else {
    memset(current_tag_uid, 0, sizeof(current_tag_uid));
    current_tag_sak = 0x00;
  }
}

/**
 * Elaborazione dei comandi APDU estratti dal blocco XfrBlock (Host -> Card)
 */
inline void decodeApduCommand(uint8_t seq, uint8_t* payload, uint32_t payload_len) {
  if (payload_len < 4) {
    uint8_t error_sw[] = { 0x6D, 0x00 }; 
    ccidSendApduResponse(seq, error_sw, sizeof(error_sw));
    return;
  }

  uint8_t cla  = payload[0];
  uint8_t ins  = payload[1];
  uint8_t p1   = payload[2];
  uint8_t p2   = payload[3];
  
  uint8_t responseBuffer[40];
  uint32_t responseLen = 0;
  memset(responseBuffer, 0, sizeof(responseBuffer));

  // CASO 1: Comando "Get Data" (FF CA 00 00 00)
  if (cla == 0xFF && ins == 0xCA && p1 == 0x00 && p2 == 0x00) {
    if (current_tag_uid_len > 0) {
      memcpy(responseBuffer, current_tag_uid, current_tag_uid_len);
      responseLen = current_tag_uid_len;
      responseBuffer[responseLen++] = 0x90;
      responseBuffer[responseLen++] = 0x00;
    } else {
      responseBuffer[responseLen++] = 0x6A; 
      responseBuffer[responseLen++] = 0x82; 
    }
  }
  // CASO 2: Comando Pass-Through PC/SC per GET_VERSION (FF 00 00 00 ...)
  else if (cla == 0xFF && ins == 0x00 && p1 == 0x00 && p2 == 0x00) {
    if (payload_len >= 6 && payload[5] == 0x60) {
      uint8_t nxpCommand[1] = { 0x60 }; 
      uint8_t hardwareResponse[20];
      uint8_t hardwareResponseLen = sizeof(hardwareResponse);
      memset(hardwareResponse, 0, sizeof(hardwareResponse));
      
      if (nfcDevice.inDataExchange(nxpCommand, 1, hardwareResponse, &hardwareResponseLen)) {
        memcpy(responseBuffer, hardwareResponse, hardwareResponseLen);
        responseLen = hardwareResponseLen;
        responseBuffer[responseLen++] = 0x90;
        responseBuffer[responseLen++] = 0x00;
      } else {
        responseBuffer[responseLen++] = 0x6F;
        responseBuffer[responseLen++] = 0x01;
      }
    } else {
      responseBuffer[responseLen++] = 0x6C; 
      responseBuffer[responseLen++] = 0x00;
    }
  }
  // CASO 3: Comando "Read Binary" (FF B0 00 [Pagina/Blocco] 04)
  else if (cla == 0xFF && ins == 0xB0 && p1 == 0x00) {
    uint8_t blockOrPage = p2;
    uint8_t dataBuffer[32]; 
    memset(dataBuffer, 0, sizeof(dataBuffer));
    
    if (current_tag_uid_len == 7) {
      if (nfcDevice.ntag2xx_ReadPage(blockOrPage, dataBuffer)) {
        memcpy(responseBuffer, dataBuffer, 4); 
        responseLen = 4;
        responseBuffer[responseLen++] = 0x90; responseBuffer[responseLen++] = 0x00;
      } else {
        responseBuffer[responseLen++] = 0x6F; responseBuffer[responseLen++] = 0x00; 
      }
    }
    else if (current_tag_uid_len == 4) {
      uint8_t defaultKey[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
      if (nfcDevice.mifareclassic_AuthenticateBlock(current_tag_uid, current_tag_uid_len, blockOrPage, 0, defaultKey)) {
        if (nfcDevice.mifareclassic_ReadDataBlock(blockOrPage, dataBuffer)) {
          memcpy(responseBuffer, dataBuffer, 16); 
          responseLen = 16;
          responseBuffer[responseLen++] = 0x90; responseBuffer[responseLen++] = 0x00;
        } else {
          responseBuffer[responseLen++] = 0x6F; responseBuffer[responseLen++] = 0x00; 
        }
      } else {
        responseBuffer[responseLen++] = 0x69; responseBuffer[responseLen++] = 0x82; 
      }
    }
  }
  // CASO 4: Comando "Update Binary" (FF D6 00 [Pagina] 04 [4 Byte Dati])
  else if (cla == 0xFF && ins == 0xD6 && p1 == 0x00) {
    uint8_t targetPage = p2; 
    
    if (payload_len >= 9) {
      uint8_t bytesToWrite[4];
      memcpy(bytesToWrite, &payload[5], 4); // I dati iniziano al byte 5 dell'APDU (dopo l'header e Lc)
      
      if (current_tag_uid_len == 7) {
        if (nfcDevice.ntag2xx_WritePage(targetPage, bytesToWrite)) {
          responseBuffer[responseLen++] = 0x90;
          responseBuffer[responseLen++] = 0x00;
        } else {
          responseBuffer[responseLen++] = 0x6F;
          responseBuffer[responseLen++] = 0x00;
        }
      } else {
        responseBuffer[responseLen++] = 0x6A; 
        responseBuffer[responseLen++] = 0x81;
      }
    } else {
      responseBuffer[responseLen++] = 0x6C; 
      responseBuffer[responseLen++] = 0x00;
    }
  }
  else {
    responseBuffer[responseLen++] = 0x6D; 
    responseBuffer[responseLen++] = 0x00; 
  }

  ccidSendApduResponse(seq, responseBuffer, responseLen);
}

inline void dispatchCcidMessage(uint8_t msg_type, uint32_t payload_len) {
  uint8_t seq = rx_buffer[6]; 
  
  switch (msg_type) {
    case PC_TO_RDR_ICCPOWERON:
      if (current_tag_uid_len > 0) {
        ccidSendStandardAtrResponse(seq, current_tag_uid, current_tag_uid_len, current_tag_sak);
      } else {
        uint8_t fallbackUid[] = {0, 0, 0, 0};
        ccidSendStandardAtrResponse(seq, fallbackUid, 4, 0x00);
      }
      break;
      
    case PC_TO_RDR_XFRBLOCK:
      decodeApduCommand(seq, &rx_buffer[10], payload_len);
      break;
      
    default:
      break;
  }
}

inline void ccidParseByte(uint8_t incomingByte) {
  if (rx_index < CCID_BUFFER_SIZE) {
    rx_buffer[rx_index++] = incomingByte;
  } else {
    rx_index = 0; 
    return;
  }
  
  if (rx_index >= 10) {
    uint8_t msg_type = rx_buffer[0];
    
    uint32_t payload_len = rx_buffer[1] | 
                          (rx_buffer[2] << 8) | 
                          (rx_buffer[3] << 16) | 
                          (rx_buffer[4] << 24);
    
    if (rx_index >= (10 + payload_len)) {
      dispatchCcidMessage(msg_type, payload_len);
      rx_index = 0; 
    }
  }
}

#endif // CCID_PARSER_H
