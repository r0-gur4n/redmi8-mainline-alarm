# Extras

Optional features for the Redmi 8. The normal image (`image/build-image.sh`)
installs none of them; it is the same clean Ubuntu as on the other phones of
this project, plus only what this phone's hardware needs. Install what you
want on the phone itself, from a checkout of this repository:

```bash
sudo extras/install.sh                  # list
sudo extras/install.sh phone-ui         # install one
sudo extras/install.sh phone-ui --remove
```

`extras/install.sh` installs packages with `apt`, so the extras apply to the
Ubuntu image only; the Arch Linux ARM + Phosh image
([07-arch.md](../docs/07-arch.md)) ships none of them.

| Feature | What it does |
|---|---|
| [phone-ui](phone-ui/) | top bar clear of the notch and rounded corners, windows open maximized, dark theme, dock favourites |
| [debug-tools](debug-tools/) | `olive-report` (one-shot hardware report) and a persistent journal |
