# Wallpapers

Drop your images here (`.jpg`, `.jpeg`, `.png`, `.webp`, `.bmp`, `.gif`). One is
enough; with more, `b-wallpaper` cycles through them. Everything in this folder
is gitignored except this file, `b-wallpaper` and `default.jpg`, so your images
stay on this machine. `default.jpg` is the one a fresh clone starts with.

```sh
b-wallpaper            # next image (also i3's $mod+Shift+w)
b-wallpaper prev       # previous image
b-wallpaper random     # any other image
b-wallpaper restore    # the last one shown — i3 runs this on login and reload
b-wallpaper list       # what it cycles through
b-wallpaper auto       # the next one every 5 minutes — i3 starts this on login
b-wallpaper auto 60    # ...or every 60 seconds
```

Delete `default.jpg` (and have no other image) to keep i3's solid Gruvbox-dark
background.
