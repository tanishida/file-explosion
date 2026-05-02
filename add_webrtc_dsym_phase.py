import re

project_path = "file-explosion.xcodeproj/project.pbxproj"
with open(project_path, "r") as f:
    text = f.read()

script = """
if [ "${ACTION}" = "install" ]; then
    # Find WebRTC framework in the built products
    WEBRTC_MAC="${BUILT_PRODUCTS_DIR}/WebRTC.framework/Versions/A/WebRTC"
    WEBRTC_IOS_1="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/WebRTC.framework/WebRTC"
    WEBRTC_IOS_2="${BUILT_PRODUCTS_DIR}/PackageFrameworks/WebRTC.framework/WebRTC"
    
    if [ -f "$WEBRTC_IOS_1" ]; then
        WEBRTC_BIN="$WEBRTC_IOS_1"
    elif [ -f "$WEBRTC_IOS_2" ]; then
        WEBRTC_BIN="$WEBRTC_IOS_2"
    elif [ -f "$WEBRTC_MAC" ]; then
        WEBRTC_BIN="$WEBRTC_MAC"
    else
        # fallback, search
        WEBRTC_BIN=$(find "${BUILT_PRODUCTS_DIR}" -name "WebRTC" -type f | grep "WebRTC.framework" | head -n 1)
    fi

    if [ -n "$WEBRTC_BIN" ] && [ -f "$WEBRTC_BIN" ]; then
        echo "Generating dSYM for WebRTC at $WEBRTC_BIN"
        dsymutil "$WEBRTC_BIN" -o "${DWARF_DSYM_FOLDER_PATH}/WebRTC.framework.dSYM"
    else
        echo "WebRTC binary not found for dSYM generation."
    fi
fi
"""

# Let's use Xcode's PBXProj manipulation via simple regex. It's safer to use an external tool, but since we are simple:
# Actually, it's easier to use a tool like `xcodeproj` ruby gem, but since it's not installed, we can just install it or use sed.
