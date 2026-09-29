# =============================================================================
# Project: ProEm - Open Source Protocol Emulator
# File: host/proem_host.py
# Type: Host library (builds ISA instruction bytes for the host link)
# Author: Paul Vincent Bezzina
# Language: Python
# Description:
# =============================================================================

SYNC, ASYNC, GENERATE, RECOVER = 0, 1, 2, 3
CLOCK_HZ = 50_000_000


def _op(code, ch, n=0):
    return (code << 4) | (ch << 3) | (n & 7)


def start(ch, val, cyc, cap, wr, pin=0):
    return [_op(1, ch), (wr << 7) | (cap << 6) | (cyc & 15), pin & 7, val & 0xFF]


def main(ch, bits, direction, we=0, ack=0, pin=0, sr=0):
    return [_op(3, ch), (direction << 6) | (we << 5) | (ack << 4) | (sr << 3) | (pin & 7), (bits >> 8) & 0xFF, bits & 0xFF]


def order(ch, msb):
    return [_op(6, ch, msb)]


def run(ch, mode=0):
    return [_op(7, ch, mode)]


def clear(ch):
    return [_op(9, ch)]


def line(ch, code, pin_a, stuff=0, pin_b=0, inv=0, sany=0):
    v = (code << 13) | (inv << 12) | ((pin_a & 7) << 8) | (sany << 7) | ((stuff & 15) << 3) | (pin_b & 7)
    return [_op(0xA, ch), (v >> 8) & 0xFF, v & 0xFF]


def clock(ch, src, div, pin=0, edge=0, idle=0, etk=0):
    v = (src << 30) | (edge << 28) | (idle << 27) | ((pin & 7) << 24) | (etk << 22) | (div & 0xFFFF)
    return [_op(0xB, ch), (v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]


def out(ch, drive, idle=0, pair=0, eop=0, i2c=0, cshigh=0):
    return [_op(0xD, ch), (drive << 6) | (idle << 5) | (pair << 4) | (eop << 3) | (i2c << 2) | (cshigh << 1)]


def data(ch, length, val):
    return [_op(0xC, ch, length - 1), val & 0xFF]


def uart_divider(baud):
    return round(CLOCK_HZ / baud)


def uart_tx_setup(ch, baud):
    div = uart_divider(baud)
    return (clear(ch) + order(ch, 0) + line(ch, 0, 0) + clock(ch, ASYNC, div)
            + out(ch, 3, idle=1) + start(ch, 0x00, 1, 0, 1) + main(ch, 9, 1))


def uart_tx_byte(ch, value):
    return data(ch, 8, value) + data(ch, 1, 1)


def uart_tx(ch, baud, payload, preload=4):
    first = uart_tx_setup(ch, baud)
    for b in payload[:preload]:
        first += uart_tx_byte(ch, b)
    first += run(ch, 0)
    rest = []
    for b in payload[preload:]:
        rest += uart_tx_byte(ch, b)
    return first, rest


def decode_return(stream):
    events = []
    for i in range(0, len(stream) - 1, 2):
        head, value = stream[i], stream[i + 1]
        if (head & 0xC0) == 0xC0:
            events.append(("link", value))
        elif (head & 0xC0) == 0x80:
            ch = (head >> 5) & 1
            length = head & 0x0F
            if length == 0x0F:
                events.append(("status", ch, value))
            else:
                events.append(("data", ch, length, value))
    return events
