"""Cuts a stretch out of an MP3 without re-encoding: keeps the whole frames between two times.

    python tools/mp3_cut.py IN.mp3 OUT.mp3 START_S END_S

(The hay rustle, audio/country/SOURCES.md: the minute between the voices on the recording.)
MPEG-1/2 Layer III frames only; ID3 tags and the first frame if it's a Xing/Info header are left out.
"""
import sys

BITRATES = {  # (mpeg version 1?, index) -> kbps, layer III
	True: [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0],
	False: [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0],
}
RATES = {3: [44100, 48000, 32000], 2: [22050, 24000, 16000], 0: [11025, 12000, 8000]}


def frames(data):
	i = 0
	if data[:3] == b"ID3":  # skip an ID3v2 tag
		size = (data[6] << 21) | (data[7] << 14) | (data[8] << 7) | data[9]
		i = 10 + size
	while i + 4 <= len(data):
		h = int.from_bytes(data[i:i + 4], "big")
		if (h >> 21) & 0x7FF != 0x7FF:
			i += 1
			continue
		version = (h >> 19) & 3
		layer = (h >> 17) & 3
		br = (h >> 12) & 0xF
		sr = (h >> 10) & 3
		pad = (h >> 9) & 1
		if layer != 1 or version == 1 or br in (0, 15) or sr == 3:  # (layer bits 01 = layer III)
			i += 1
			continue
		mpeg1 = version == 3
		rate = RATES[version][sr]
		kbps = BITRATES[mpeg1][br]
		samples = 1152 if mpeg1 else 576
		length = samples // 8 * kbps * 1000 // rate + pad
		yield i, length, samples / rate
		i += length


def main():
	src, dst, t0, t1 = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
	data = open(src, "rb").read()
	out = bytearray()
	t = 0.0
	first = True
	for at, length, dur in frames(data):
		chunk = data[at:at + length]
		if first:
			first = False
			if b"Xing" in chunk or b"Info" in chunk:
				continue
		if t0 <= t < t1:
			out += chunk
		t += dur
	open(dst, "wb").write(out)
	print("kept %.1f s of %.1f s, %d bytes" % (min(t1, t) - t0, t, len(out)))


if __name__ == "__main__":
	main()
