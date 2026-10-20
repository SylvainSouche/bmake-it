#!/usr/bin/env python3
# @impl 0f87-6ad7-1929-a1bb
"""console.py SOCKET -- drive a guest serial console. Reads script lines on stdin:
   expect:<regex>   wait (timeout 120s) for regex in the output
   send:<text>      send text + newline
Prints everything the guest writes."""
import socket, sys, re, time, select
sock = socket.socket(socket.AF_UNIX); 
for _ in range(60):
    try: sock.connect(sys.argv[1]); break
    except OSError: time.sleep(1)
buf = ''
def read(t):
    global buf
    r,_,_ = select.select([sock],[],[],t)
    if r:
        d = sock.recv(65536).decode('utf-8','replace'); sys.stdout.write(d); sys.stdout.flush(); buf += d; return True
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
end=time.time()+3
while time.time()<end: read(0.5)
