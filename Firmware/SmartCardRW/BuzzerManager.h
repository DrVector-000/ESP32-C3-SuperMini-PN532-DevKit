//********************************************************************************************************//
// Nome Modulo: BuzzerManager.h
// Descrizione: Libreria per la gestione del Buzzer e dei relativi segnali acustici di feedback.
//********************************************************************************************************//

#ifndef BUZZER_MANAGER_H
#define BUZZER_MANAGER_H

#include <Arduino.h>

#define BUZZER_PIN       0
#define BUZZER_CHANNEL   0

/**
 * Inizializzazione del modulo PWM hardware per il buzzer
 */
inline void buzzerInit() {
  ledcSetup(BUZZER_CHANNEL, 2000, 8);
  ledcAttachPin(BUZZER_PIN, BUZZER_CHANNEL);
  ledcWriteTone(BUZZER_CHANNEL, 0);
}

/**
 * Generazione di un tono acustico temporizzato alla frequenza specificata
 */
inline void buzzerBeep(int duration_ms, int frequency_hz) {
  ledcWriteTone(BUZZER_CHANNEL, frequency_hz);
  delay(duration_ms);
  ledcWriteTone(BUZZER_CHANNEL, 0);
}

/**
 * Segnale acustico di avvio del firmware
 */
inline void buzzerPlayBootTone() {
  buzzerBeep(100, 1500);
}

/**
 * Feedback acustico per inserimento o rilevamento carta
 */
inline void buzzerPlayCardInserted() {
  buzzerBeep(80, 1000);
}

/**
 * Feedback acustico per rimozione carta
 */
inline void buzzerPlayCardRemoved() {
  buzzerBeep(50, 1000);
  delay(40);
  buzzerBeep(50, 1000);
}

/**
 * Segnale acustico per errore hardware
 */
inline void buzzerPlayErrorTone() {
  for (int i = 0; i < 3; i++) {
    buzzerBeep(300, 600);
    delay(100);
  }
}

#endif // BUZZER_MANAGER_H
