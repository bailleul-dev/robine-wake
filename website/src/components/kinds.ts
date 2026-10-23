export const KINDS = {
  power: "Power (+)",
  "3v3": "3.3 V",
  gnd: "Ground",
  uart: "UART",
  i2s: "I²S audio",
  i2c: "I²C",
  spi: "SPI",
  signal: "Signal",
  audio: "Speaker",
  usb: "USB",
} as const;
export type Kind = keyof typeof KINDS;
