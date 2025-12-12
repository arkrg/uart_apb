# UART Register Map (DLAB-based, 16550-style)

This document describes the memory-mapped register structure of the UART module.  
The mapping of certain registers depends on the value of the DLAB (Divisor Latch Access Bit), which is LCR\[7\].

---

## 📐 Register Address Map

| Address (Offset) | DLAB = 0           | DLAB = 1           | Access | Description |
|------------------|--------------------|--------------------|--------|-------------|
| `0x00`           | THR (TX Write)     | DLL (Divisor LSB)  | R/W    | Transmit data or baud rate LSB |
| `0x00`           | RBR (RX Read)      | DLL (Divisor LSB)  | R/W    | Received data or baud rate LSB |
| `0x04`           | IER (Interrupt Enable) | DLH (Divisor MSB)  | R/W    | Interrupt or baud rate MSB |
| `0x08`           | IIR (Interrupt ID) | IIR (same)         | R      | Interrupt source (Read-only) |
| `0x08`           | FCR (FIFO Control) | FCR (same)         | W      | FIFO control (Write-only) |
| `0x0C`           | LCR (Line Control) | LCR (same)         | R/W    | Format control and DLAB bit |
| `0x10`           | MCR (Modem Control)| MCR (same)         | R/W    | Modem signals (optional) |
| `0x14`           | LSR (Line Status)  | LSR (same)         | R      | TX/RX status (e.g., THRE, TEMT, DR) |
| `0x18`           | MSR (Modem Status) | MSR (same)         | R      | Modem status (RTS/CTS, optional) |
| `0x1C`           | SCR (Scratch)      | SCR (same)         | R/W    | Scratch register (user-defined) |

> ⚠️ Note: LCR\[7\] is the DLAB bit  
> - When DLAB = 1, addresses `0x00` and `0x04` are used for DLL/DLH  
> - When DLAB = 0, they are used for RBR/THR and IER respectively

---

## 🧾 Register Descriptions

### 🔸 THR (Transmit Holding Register)
- Address: `0x00` (write-only, DLAB = 0)
- Used to write data to transmit

### 🔹 RBR (Receiver Buffer Register)
- Address: `0x00` (read-only, DLAB = 0)
- Used to read received data

### 🔸 DLL / DLH (Divisor Latches)
- Address: `0x00`, `0x04` (DLAB = 1)
- 16-bit divisor for baud rate generation

### 🔹 LCR (Line Control Register)
- Address: `0x0C`
- Controls:
  - Word length (5–8 bits)
  - Parity enable/type
  - Stop bit configuration
  - DLAB bit (LCR\[7\])

### 🔸 LSR (Line Status Register)
- Address: `0x14`
- Read-only status signals:
  - bit\[0\] DR: Data Ready
  - bit\[5\] THRE: Transmit Holding Register Empty
  - bit\[6\] TEMT: Transmitter Empty

---

## ✅ Example: Setting the Baud Rate

1. Set `LCR[7] = 1` (enable access to DLL/DLH)
2. Write divisor value to DLL and DLH
3. Clear `LCR[7] = 0` (resume normal data access)

---

## 📎 Notes

- All registers are 32-bit aligned (offsets are multiples of 4)
- Optional features like FIFO or interrupt can be omitted

