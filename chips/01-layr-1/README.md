# 01-layr-1

**Author:** Thomas Gingele, Marcel Hofmann, Jan Schaible, Felix Schladt

## Description

This chip is a secure door lock chip that implements Level 1 of the LAYR challenge.
When an NFC card is presented, it runs an AES-based challenge-response authentication protocol to verify the card holds the correct pre-shared secret.
The card ID is transmitted encrypted using a session key derived from a mutual challenge exchange, preventing eavesdropping attacks.
Only if both the authentication and ID verification succeed will the chip trigger the door lock to open.

## Pin List

| Pin | Direction | Description |
|---|---|---|
| `rst_PAD` | Input | Synchronous reset |
| `clk_PAD` | Input | Main clock |
| `cs_0_PAD` | Output | SPI chip select — MFRC522 NFC reader |
| `cs_1_PAD` | Output | SPI chip select — AT25010B EEPROM |
| `spi_sclk_PAD` | Output | SPI clock |
| `spi_mosi_PAD` | Output | SPI data out (master → peripheral) |
| `spi_miso_PAD` | Input | SPI data in (peripheral → master) |
| `status_unlock_PAD` | Output | Door unlock signal |
| `status_fault_PAD` | Output | Authentication failed indicator |
| `status_busy_PAD` | Output | Authentication in progress indicator 

# Building the chip

export PDK_ROOT="$(pwd)/pdk"


```sh
nix-shell librelane
cd chips/01-layr-1/design_data/layr/layr/Chip/
make librelane

#cd ../../top-image
#mkdir gds
#make img2gds
#make drc
#make insert_img
#make klayout-final
```

Unfortunately, we forgot to include the boundaries specified in the top image in our final run:

```yaml
PDN_OBSTRUCTIONS:
  - [TopMetal2, 450, 450, 750, 600]

ROUTING_OBSTRUCTIONS:
  - [TopMetal2, 450, 450, 750, 600]
```
As a result — and especially considering that the final run took three days to complete — the generated gds does not contain the image in the top metal layer.