import os
from PIL import Image

folder = r"c:\KesifApp"
for f in os.listdir(folder):
    if f.lower().endswith(".png"):
        path = os.path.join(folder, f)
        try:
            with Image.open(path) as img:
                print(f"{f}: {img.width}x{img.height}")
        except Exception as e:
            print(f"Error reading {f}: {e}")
