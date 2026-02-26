
#include <SPI.h>


// VSPI default pins
#define PIN_MOSI 23
#define PIN_MISO 19
#define PIN_SCK  18
#define PIN_CS   5

SPIClass spi(VSPI);

// SPI Settings: 1 Mbps, MSB first, Mode 0
SPISettings spiSettings(1000000, MSBFIRST, SPI_MODE0);

uint8_t spiTransfer(uint8_t *tx_data)
{
  uint8_t rx_data[2];

  spi.beginTransaction(spiSettings);
  digitalWrite(PIN_CS, LOW);

  spi.transferBytes(tx_data, rx_data, 2); 

  digitalWrite(PIN_CS, HIGH);
  spi.endTransaction();

  return rx_data[1];
}

void setup()
{
  Serial.begin(115200);

  pinMode(PIN_CS, OUTPUT);
  digitalWrite(PIN_CS, HIGH);

  spi.begin(PIN_SCK, PIN_MISO, PIN_MOSI, PIN_CS);

  Serial.println("SPI Master 12-bit Example");
}

void build_bytes(uint8_t addr, uint16_t data, uint8_t *bytes) {

  bytes[0] = (addr & 0xF) << 4;
  bytes[0] = bytes[0] | (data >> 8);
  bytes[1] = data & 0xFF;
}

void loop()
{
  uint8_t reg_address;
  uint16_t reg_data;
  uint8_t tx[2];

  for (int i = 0; i <=0xFFF; i++) { 
    reg_address = 0xA;
    reg_data = 0x00 + i;

    build_bytes(reg_address, reg_data, tx);

    Serial.print("b1 -> b");
    Serial.print(tx[0], BIN);
    
    Serial.print(" b2 -> b");
    Serial.println(tx[1], BIN);


    uint8_t rxValue = spiTransfer(tx);
    Serial.print("  RX: 0x");
    Serial.println(rxValue, HEX);
    delay(100);
  }

/*
*/
  
}
