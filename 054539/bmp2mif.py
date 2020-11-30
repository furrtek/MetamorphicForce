from PIL import Image

def conv(filename):
    global i

    im = Image.open(filename)
    pixels = im.load()

    for ty in range(im.size[1] / 16):
        for tx in range(im.size[0] / 16):
            for y in range(16):
                color = 0
                for x in range(16):
                    color <<= 2
                    color += (pixels[tx * 16 + x, ty * 16 + y][0] >> 6)
                f.write(format(i, 'X') + " : " + format(color, 'X') + ";\n")
                i += 1

i = 0
f = open("chip.mif", "w")
f.write("DEPTH = 2048;\n")
f.write("WIDTH = 32;\n")
f.write("ADDRESS_RADIX = HEX;\n")
f.write("DATA_RADIX = HEX;\n")
f.write("CONTENT\n")
f.write("BEGIN\n")

conv("chip.bmp")
conv("kromasky_16x16.png")

f.write("END;\n")

f.close()
