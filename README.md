# TestAddon

Just testing video+sound playback as a WoW addon

## Setting it up

1. Install ffmpeg and have it in your PATH

2. Run the python script

```sh
python encode.py file.mp4
```

It should spit out two files: `frames.lua` and `sound.mp3`.

## Modifying the parameters

You can modify the vidoe parameters in `encode.py` and `TestAddon.lua` with the following variables:

```
fps
width
height
block_size
frame_delta_threshold (r/g/b difference threshold for persisting a frame delta)
```

> [!IMPORTANT]
> WoW has a limitation of around ~16k frame elements to be rendered on the screen at one given time. If you're modifying the `block_size` and `width` / `height`, keep in mind it has to satisfy: `[width]*[height]/([block_size]^2) <= 16000`.
