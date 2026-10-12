# Wallpapers

Drop your images here (`.jpg`, `.jpeg`, `.png`, `.webp`, `.bmp`, `.gif`). One is
enough; with more, `b-wallpaper` cycles through them. Everything in this folder
is gitignored except this file and `b-wallpaper`, so the images stay on this
machine.

```sh
b-wallpaper            # next image (also i3's $mod+Shift+w)
b-wallpaper prev       # previous image
b-wallpaper random     # any other image
b-wallpaper restore    # the last one shown — i3 runs this on login and reload
b-wallpaper list       # what it cycles through
```

With no image here, i3 keeps its solid Gruvbox-dark background.
