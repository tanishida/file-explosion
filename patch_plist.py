import plistlib

with open("file-explosion/Info.plist", "rb") as f:
    pl = plistlib.load(f)

pl["NSCameraUsageDescription"] = "アプリ内で直接、安全に写真や動画を撮影してシークレット領域に保存するためにカメラを使用します。"
pl["NSMicrophoneUsageDescription"] = "アプリ内で安全に動画を撮影（録音）してシークレット領域に保存するためにマイクを使用します。"

with open("file-explosion/Info.plist", "wb") as f:
    plistlib.dump(pl, f)
