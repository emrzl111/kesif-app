import os
import json
import glob

brain_dir = r"C:\Users\Asus\.gemini\antigravity-ide\brain"

session_dirs = [d for d in os.listdir(brain_dir) if os.path.isdir(os.path.join(brain_dir, d)) and d != "tempmediaStorage"]

print(f"Found {len(session_dirs)} session directories.")

for s in session_dirs:
    s_path = os.path.join(brain_dir, s)
    transcript_path = os.path.join(s_path, ".system_generated", "logs", "transcript.jsonl")
    
    print(f"\n================ SESSION: {s} ================")
    
    # List artifacts in session folder
    md_files = glob.glob(os.path.join(s_path, "*.md"))
    if md_files:
        print("  Artifacts:", [os.path.basename(f) for f in md_files])
    
    if os.path.exists(transcript_path):
        with open(transcript_path, "r", encoding="utf-8") as f:
            for line in f:
                try:
                    data = json.loads(line)
                    if data.get("type") == "USER_INPUT":
                        content = data.get("content", "")
                        # Extract string inside <USER_REQUEST> if present
                        if "<USER_REQUEST>" in content:
                            req = content.split("<USER_REQUEST>")[1].split("</USER_REQUEST>")[0].strip()
                            print(f"  [USER INPUT] {req}")
                        else:
                            print(f"  [USER INPUT RAW] {content[:200]}")
                except Exception as e:
                    pass
