# Firmware de test Rust pour NodeMCU ESP8266 (LED + port série).
# Prérequis : `espup install` (compilateur Rust esp), GCC xtensa-lx106 d'Espressif
# dans ~/.local/opt/xtensa-lx106-elf, et `esptool` (uv tool install esptool).

LX106 ?= $(HOME)/.local/opt/xtensa-lx106-elf/bin
PORT ?= /dev/ttyUSB0
BAUD ?= 115200
ELF := target/xtensa-esp8266-none-elf/release/esp8266-hello
IMG := target/esp8266-hello-

export PATH := $(LX106):$(PATH)

.PHONY: build image flash monitor clean

build:
	cargo build --release

image: build
	esptool --chip esp8266 elf2image --version 1 -o $(IMG) $(ELF)

flash: image
	esptool --chip esp8266 --port $(PORT) write-flash 0x00000 $(IMG)0x00000.bin 0x10000 $(IMG)0x10000.bin

monitor:
	uvx --from pyserial pyserial-miniterm --raw $(PORT) $(BAUD)

clean:
	cargo clean
