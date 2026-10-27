#!/usr/bin/env python3
# @impl 0f87-6ad7-1929-a1bb
"""console.py SOCKET|HOST:PORT -- drive a guest serial console. Reads script lines on stdin:
   expect:<regex>   wait (timeout 120s) for regex in the output
   send:<text>      send text + newline
   slow:<text>      the same, typed one character at a time
   key:<chars>      press these keys one at a time, no newline
A boot loader (BIOS, FreeBSD's and NetBSD's) reads the serial port while it
polls, a byte at a time: bytes that arrive together are lost but the last
(the newline, which picks a menu's default) -- type to it with slow:/key:.
Prints everything the guest writes. HOST:PORT is a TCP console (a native
Windows QEMU cannot serve a Cygwin unix socket)."""
import socket, sys, re, time, select
target = sys.argv[1]
tcp = re.fullmatch(r'([0-9.]+|localhost):([0-9]+)', target)
for _ in range(60):
    sock = socket.socket(socket.AF_INET if tcp else socket.AF_UNIX)
    try:
        sock.connect((tcp.group(1), int(tcp.group(2))) if tcp else target); break
    except OSError:
        sock.close(); time.sleep(1)
else:
    print('!! cannot connect to the guest console', target); sys.exit(4)
buf = ''
def read(t):
    global buf
    r,_,_ = select.select([sock],[],[],t)
    if r:
        try:
            d = sock.recv(65536)
        except OSError:
            d = b''
        if not d:
            # the guest exited (a reboot under -no-reboot): vm.sh boots it again
            print('\n!! console closed: the guest exited'); sys.exit(5)
        d = d.decode('utf-8','replace'); sys.stdout.write(d); sys.stdout.flush(); buf += d; return True
    return False
for line in sys.stdin:
    line=line.rstrip('\n')
    if line.startswith('expect:'):
        rx = re.compile(line[7:]); end=time.time()+180
        while not rx.search(buf):
            if time.time()>end: print('\n!! TIMEOUT waiting for', line[7:]); sys.exit(3)
            read(1)
        buf = ''
    elif line.startswith('send:'):
        sock.sendall((line[5:]+'\r').encode()); time.sleep(0.4)
    elif line.startswith('slow:') or line.startswith('key:'):
        keys = line[5:] + '\r' if line.startswith('slow:') else line[4:]
        for k in keys:
            sock.sendall(k.encode()); read(0.25)
        time.sleep(0.4)
end=time.time()+3
while time.time()<end: read(0.5)
