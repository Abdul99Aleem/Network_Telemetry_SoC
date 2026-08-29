# SoC Top-Level Ports

| Port | Direction | Width | Type | Description |
|---|---|---:|---|---|
| `clk` | Input | 1 | Clock | Main synchronous system clock |
| `reset` / `reset_n` | Input | 1 | Reset | Global SoC reset; polarity follows the supplied VeeR/faculty wrapper |
| `pkt_valid` | Input | 1 | Streaming control | Indicates that `pkt_data` contains a valid packet byte |
| `pkt_data[7:0]` | Input | 8 | Streaming data | 8-bit incoming network packet byte |
| `pkt_last` | Input | 1 | Streaming control | Indicates the final byte of the current packet |
| `uart_tx` | Output | 1 | Serial | UART transmit output for telemetry/status reporting |
| `gpio[3:0]` | Output | 4 | Status/debug | External GPIO/status outputs |

# VeeR EL2 ↔ AHB-Lite Interconnect

| Signal | Direction | Width | Description |
|---|---|---:|---|
| `HADDR` | Master → Interconnect | 32 | Address of the current transfer |
| `HTRANS` | Master → Interconnect | 2 | Transfer type |
| `HWRITE` | Master → Interconnect | 1 | `1` = write, `0` = read |
| `HSIZE` | Master → Interconnect | 3 | Transfer size |
| `HBURST` | Master → Interconnect | 3 | Burst type information |
| `HPROT` | Master → Interconnect | 4 | Protection/access attributes |
| `HWDATA` | Master → Interconnect | 32 | Write data |
| `HRDATA` | Interconnect → Master | 32 | Read data |
| `HREADY` | Interconnect → Master | 1 | Transfer completion / wait-state indication |
| `HRESP` | Interconnect → Master | 1 | Transfer response |

# AHB-Lite Interconnect → Peripheral Slaves

| Signal | Direction | Width | Description |
|---|---|---:|---|
| `HADDR` | Interconnect → Slave | 32 | Address |
| `HTRANS` | Interconnect → Slave | 2 | Transfer type |
| `HWRITE` | Interconnect → Slave | 1 | Read/write control |
| `HSIZE` | Interconnect → Slave | 3 | Transfer size |
| `HBURST` | Interconnect → Slave | 3 | Burst type |
| `HPROT` | Interconnect → Slave | 4 | Access attributes |
| `HWDATA` | Interconnect → Slave | 32 | Write data |
| `HSEL_x` | Interconnect → Slave | 1 | Slave select |
| `HRDATA` | Slave → Interconnect | 32 | Read data |
| `HREADY` | Slave → Interconnect | 1 | Transfer completion / wait-state indication |
| `HRESP` | Slave → Interconnect | 1 | Transfer response |

# Packet Streaming Interface

| Signal | Direction | Width | Description |
|---|---|---:|---|
| `pkt_valid` | Input | 1 | Indicates a valid packet byte |
| `pkt_data[7:0]` | Input | 8 | Incoming packet byte |
| `pkt_last` | Input | 1 | Indicates the final byte of the packet |

# Network Telemetry Engine Interface

| Interface / Signal | Direction | Width | Description |
|---|---|---:|---|
| `pkt_valid` | Input | 1 | Valid packet byte |
| `pkt_data[7:0]` | Input | 8 | Packet byte stream |
| `pkt_last` | Input | 1 | End-of-packet indication |
| `crc_result/status` | Input | Implementation-dependent | CRC result/status associated with the packet |
| `NET_IRQ` | Output | 1 | Packet/event interrupt to VeeR |

# AES-128 Interface

| Register | Offset | Width | Description |
|---|---:|---:|---|
| `CONTROL` | `0x00` | 32 | AES control/start |
| `STATUS` | `0x04` | 32 | AES status |
| `KEY0` | `0x08` | 32 | AES key word 0 |
| `KEY1` | `0x0C` | 32 | AES key word 1 |
| `KEY2` | `0x10` | 32 | AES key word 2 |
| `KEY3` | `0x14` | 32 | AES key word 3 |
| `DATA0` | `0x18` | 32 | Plaintext word 0 |
| `DATA1` | `0x1C` | 32 | Plaintext word 1 |
| `DATA2` | `0x20` | 32 | Plaintext word 2 |
| `DATA3` | `0x24` | 32 | Plaintext word 3 |
| `RESULT0` | `0x28` | 32 | Ciphertext word 0 |
| `RESULT1` | `0x2C` | 32 | Ciphertext word 1 |
| `RESULT2` | `0x30` | 32 | Ciphertext word 2 |
| `RESULT3` | `0x34` | 32 | Ciphertext word 3 |

**AES base address:** `0x1000_4000`

# CRC32 Interface

| Register | Offset | Width | Description |
|---|---:|---:|---|
| `CONTROL` | `0x00` | 32 | CRC control/reset |
| `STATUS` | `0x04` | 32 | CRC status |
| `DATA` | `0x08` | 32 | Data/control access |
| `RESULT` | `0x0C` | 32 | CRC result and status |

**CRC32 base address:** `0x1000_5000`

# GPIO Interface

| Signal | Direction | Width | Description |
|---|---|---:|---|
| `gpio[0]` | Output | 1 | `CPU_ALIVE` |
| `gpio[1]` | Output | 1 | `PKT_RX` |
| `gpio[2]` | Output | 1 | `AES_BUSY` |
| `gpio[3]` | Output | 1 | `PKT_ERR` |

**GPIO base address:** `0x1000_2000`

# Interrupt Interfaces

| Signal | Direction | Width | Description |
|---|---|---:|---|
| `NET_IRQ` | Telemetry → VeeR | 1 | Packet/event interrupt |
| `TIMER_IRQ` | Timer → VeeR | 1 | Timer interrupt |
| `AES_IRQ` | AES → VeeR | 1 | AES completion interrupt, if implemented |

# Memory Map

| Address Range | Size | Block | Description |
|---|---:|---|---|
| `0x0000_0000 – 0x0000_7FFF` | 32 KB | IMEM | Instruction memory |
| `0x0001_0000 – 0x0001_7FFF` | 32 KB | DMEM | Data memory |
| `0x1000_0000 – 0x1000_0FFF` | 4 KB | UART | UART registers |
| `0x1000_1000 – 0x1000_1FFF` | 4 KB | Timer | Timer registers |
| `0x1000_2000 – 0x1000_2FFF` | 4 KB | GPIO | GPIO registers |
| `0x1000_3000 – 0x1000_3FFF` | 4 KB | Network Telemetry Engine | Telemetry registers |
| `0x1000_4000 – 0x1000_4FFF` | 4 KB | AES-128 | AES registers |
| `0x1000_5000 – 0x1000_5FFF` | 4 KB | CRC32 | CRC registers |
