import serial
import time

class SerialDevice:

    # Private attributes
    __serial = serial.Serial()

    # Constructor
    def __init__(self, baudrate):
        self.__serial.baudrate = baudrate

    # Private methods

    # Public methods
    def open(self):
        self.__serial.open()
        print('Open ' + repr(self.__serial.port) + ',' + repr(self.__serial.baudrate))

    def close(self):
        self.__serial.close()
        print('Close ' + repr(self.__serial.port))

    def setport(self, port):
        self.__serial.port = port

    def is_open(self):
        """Verifica se la porta seriale è attualmente aperta."""
        return self.__serial.is_open

    def read_bytes(self):
        """
        Legge i byte disponibili nel buffer seriale in modo non bloccante.
        Ritorna un'array di byte (bytes) o None se non ci sono dati.
        """
        if self.__serial.is_open and self.__serial.in_waiting > 0:
            return self.__serial.read(self.__serial.in_waiting)
        return None

    def write_bytes(self, byte_array):
        """Invia un array di byte (o una lista) sulla porta seriale."""
        if self.__serial.is_open:
            self.__serial.write(bytes(byte_array))
            print('Write: ' + " ".join(f"{b:02X}" for b in byte_array))
