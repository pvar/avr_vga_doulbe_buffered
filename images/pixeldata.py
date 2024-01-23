from PIL import Image

img_object = Image.open("C:\logo.bmp")

pixel_array = img_object.load()

img_width = img_object.size[0]
img_height = img_object.size[1]

print "\n"
print "file format :", img_object.format
print "color format:", img_object.mode
print "image width :", img_width
print "image height:", img_height
print "\n"

lim = img_width - 1

for y in range(0, img_height):
	print ".db",
	for x in range(0, img_width):
		r = pixel_array[x, y][0]
		g = pixel_array[x, y][1]
		b = pixel_array[x, y][2]
		m = (r + g + b) / 3
		r = (r >> 6) & 0b00000011
		g = (g >> 4) & 0b00001100
		b = (b >> 2) & 0b00110000
		m = m & 0b11000000
		byte = m + r + g + b
		if x < lim: print str(byte)+",",
		else: print str(byte)