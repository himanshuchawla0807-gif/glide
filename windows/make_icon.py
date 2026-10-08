"""Generate original Glide application artwork; Python standard library only."""
import math
import struct
import zlib
from pathlib import Path
n = 256
pixels = bytearray()
for y in range(n):
    pixels.append(0)
    for x in range(n):
        dx, dy = x - 127.5, y - 127.5
        edge = math.hypot(max(abs(dx)-76, 0), max(abs(dy)-76, 0))
        alpha = max(0, min(1, 48-edge))
        radius, angle = math.hypot(dx,dy), math.atan2(dy,dx)
        ribbon = math.exp(-((radius-(69+7*math.sin(angle*3))) / 4.5)**2)
        ribbon += .5*math.exp(-((radius-(54+9*math.sin(angle*2+1))) / 3)**2)
        glow = .4*math.exp(-((radius-64)/21)**2)
        light = min(1,ribbon+glow)
        pixels.extend((int(23+185*light),int(19+155*light),int(35+220*light),int(255*alpha)))
def chunk(kind, data):
    return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',n,n,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(bytes(pixels),9))+chunk(b'IEND',b'')
folder=Path(__file__).parent/'src-tauri/icons'
folder.mkdir(exist_ok=True)
(folder/'icon.png').write_bytes(png)
(folder/'icon.ico').write_bytes(struct.pack('<HHH',0,1,1)+struct.pack('<BBBBHHII',0,0,0,0,1,32,len(png),22)+png)
