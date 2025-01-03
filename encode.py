import subprocess
import sys

def pack_rgb(r, g, b):
    """pack RGB into a more compact format"""
    # 6-6-4 bit color format
    r = (r >> 2) & 0x3F  # 6 bits for red
    g = (g >> 2) & 0x3F  # 6 bits for green
    b = (b >> 4) & 0x0F  # 4 bits for blue
    return (r << 10) | (g << 4) | b

def compute_frame_deltas(prev_frame, curr_frame, threshold=5):
    deltas = []
    for i in range(0, len(curr_frame), 3):
        r, g, b = curr_frame[i:i+3]
        pr, pg, pb = prev_frame[i:i+3]

        diff_r = abs(r - pr)
        diff_g = abs(g - pg)
        diff_b = abs(b - pb)
        
        # skip delta if differences exceed the threshold
        if diff_r > threshold or diff_g > threshold or diff_b > threshold:
            curr_packed = pack_rgb(r, g, b)
            deltas.append(i // 3)
            deltas.append(curr_packed)
    return deltas

def encode_rle_deltas(delta_frame):
    rle_data = []
    i = 0
    while i < len(delta_frame):
        pos = delta_frame[i]
        value = delta_frame[i + 1]

        # start run
        run_length = 1
        while i + 2 < len(delta_frame) and delta_frame[i + 2] == pos + run_length and delta_frame[i + 3] == value:
            run_length += 1
            i += 2
    
        if run_length > 1:
            # pos | 0x8000 = high bit to signify a run
            rle_data.extend([pos | 0x8000, run_length, value]) 
        else:
            rle_data.extend([pos, value])
        
        i += 2
    
    return rle_data


def convert_to_delta_lua_with_keyframes(input_stream, frame_size, keyframe_interval=60, frame_delta_threshold=5):
    """Convert stream with optimized delta encoding."""
    first_frame = list(input_stream.read(frame_size))
    prev_frame = first_frame.copy()
    
    packed_first = [pack_rgb(*first_frame[i:i+3]) for i in range(0, frame_size, 3)]
    
    lua_frames = ["{true," + ",".join(map(str, packed_first)) + "}"]

    frame_count = 1
    while True:
        raw_data = input_stream.read(frame_size)
        if not raw_data:
            break

        curr_frame = list(raw_data)
        frame_count += 1

        if frame_count % keyframe_interval == 0:
            packed_frame = [pack_rgb(*curr_frame[i:i+3]) for i in range(0, frame_size, 3)]
            lua_frames.append("{true," + ",".join(map(str, packed_frame)) + "}")
            prev_frame = curr_frame.copy()
        else:
            delta_frame = compute_frame_deltas(prev_frame, curr_frame, frame_delta_threshold)
            rle_delta = encode_rle_deltas(delta_frame)
            lua_frames.append("{false," + ",".join(map(str, rle_delta)) + "}")
            prev_frame = curr_frame.copy()

    return lua_frames

def run_ffmpeg(command):
    return subprocess.Popen(command, stdout=subprocess.PIPE)


def write_to_lua_file(lua_frames, output_file):
    """write the Lua frames to an output file."""
    with open(output_file, "w") as file:
        file.write("FrameData = {\n")
        # FrameData = { [<keyframe:bool>, 
        file.write(",\n".join(lua_frames))
        file.write("\n}\n")

def extract_audio(input_video, audio_output_file):
    """Extract audio from the video to a file."""
    ffmpeg_command = [
        "ffmpeg", "-i", input_video,
        "-t", "60", # limit to 60 seconds
        #"-ss", "00:11:35.000",
        "-q:a", "0", "-map", "a", audio_output_file,
    ]
    subprocess.run(ffmpeg_command)
    print(f"Audio extracted to: {audio_output_file}")

def process_video(input_video, fps=15, width=480, height=260, block_size=3, keyframe_interval=60, frame_delta_threshold=5):
    """extracts frame data with delta encoding""" 
    block_width = width // block_size
    block_height = height // block_size
    output_file = "frames.lua"
    audio_output_file = "sound.mp3"

    ffmpeg_video_command = [
        "ffmpeg", "-i", input_video,
        "-t", "60", # limit to 60 seconds
        #"-ss", "00:11:35.000",
        "-vf", f"fps={fps},scale={block_width}:{block_height},format=rgb24",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-"
    ]
    frame_size = block_width * block_height * 3
    process = run_ffmpeg(ffmpeg_video_command)
    lua_frames = convert_to_delta_lua_with_keyframes(process.stdout, frame_size, keyframe_interval)
    process.stdout.close()
    process.wait()

    write_to_lua_file(lua_frames, output_file)
    print(f"Lua frame data with deltas written to: {output_file}")

    # Extract audio
    extract_audio(input_video, audio_output_file)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python encode.py <path_to_video>")
        sys.exit(1)

    fps = 15

    # Canvas size
    width, height = 480, 260 # 240, 130 # 384, 208  # 720, 390

    # Block size on the pixel grid
    # Lower than 3 is better, but you'll need to use a smaller canvas
    block_size = 3

    # Interval between keyframes
    # lower value = higher quality, larger file size
    keyframe_interval = 60

    # Threshold of r/g/b difference to be considered a delta
    # Lower value = higher quality, larger file size
    frame_delta_threshold = 5

    input_video = sys.argv[1]
    process_video(
        input_video, 
        fps=fps,
        width=width,
        height=height,
        block_size=block_size,
        keyframe_interval=keyframe_interval,
        frame_delta_threshold=frame_delta_threshold
    )