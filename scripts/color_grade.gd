class_name ColorGrade
## Builds the colour-grading lookup table (a small 3D texture, the Environment's
## adjustment_color_correction) from two tints: one for the darks, one for the brights. The time of
## day's grade (cool blue nights, a warm dusk) and the biome's (BiomeMood shadow_tint /
## highlight_tint) multiply together; DayNightSky rebuilds the table when the result changes.

const SIZE := 16


## The table: every colour's darks pulled toward `shadows`, its brights toward `highlights`.
static func make_lut(shadows: Color, highlights: Color) -> ImageTexture3D:
	var images: Array[Image] = []
	for b in SIZE:
		var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
		for g in SIZE:
			for r in SIZE:
				var c := Color(r / (SIZE - 1.0), g / (SIZE - 1.0), b / (SIZE - 1.0))
				var lum := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
				var dark := (1.0 - lum) * (1.0 - lum)
				var bright := lum * lum
				var tint := Color.WHITE.lerp(shadows, dark) * Color.WHITE.lerp(highlights, bright)
				img.set_pixel(r, g, Color(clampf(c.r * tint.r, 0, 1), clampf(c.g * tint.g, 0, 1),
						clampf(c.b * tint.b, 0, 1)))
		images.append(img)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGB8, SIZE, SIZE, SIZE, false, images)
	return tex
