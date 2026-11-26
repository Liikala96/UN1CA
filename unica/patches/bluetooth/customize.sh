SOURCE_FIRMWARE_PATH="$(cut -d "/" -f 1 -s <<< "$SOURCE_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$SOURCE_FIRMWARE")"

if [[ "$(sha1sum "$WORK_DIR/system/system/apex/com.android.bt.apex" | cut -d " " -f 1)" != \
        "$(sha1sum "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/apex/com.android.bt.apex" | cut -d " " -f 1)" ]]; then
    LOG "\033[0;33m! Nothing to do\033[0m"
    unset SOURCE_FIRMWARE_PATH
    return 0
fi

# [
BUILD_APK_IN_APEX()
{
    local INPUT_FILE="$1"
    local OUTPUT_FILE

    if [[ "$INPUT_FILE" == *"javalib"* ]]; then
        OUTPUT_FILE="$WORK_DIR/system/system/framework/$(basename "$INPUT_FILE")"
    else
        OUTPUT_FILE="$WORK_DIR/system/system/${INPUT_FILE/$TMP_DIR\/unknown\/apex_payload\//}"
    fi

    if [ -d "$APKTOOL_DIR/${OUTPUT_FILE//$WORK_DIR\/system\//}" ]; then
        LOG "- Building ${INPUT_FILE//$TMP_DIR\/unknown\//}"
        "$SRC_DIR/scripts/apktool.sh" b "system" "${OUTPUT_FILE//$WORK_DIR\/system\//}" > /dev/null
        if [[ "$OUTPUT_FILE" == *".jar" ]]; then
            LOG "- Zipaligning ${INPUT_FILE//$TMP_DIR\/unknown\//}"
        else
            LOG "- Signing ${INPUT_FILE//$TMP_DIR\/unknown\//}"
        fi

        mv -f "$OUTPUT_FILE" "$INPUT_FILE"

        if [[ "$OUTPUT_FILE" == *".apk" ]]; then
            rm -rf "$(dirname "${APKTOOL_DIR:?}/${OUTPUT_FILE//$WORK_DIR\/system\//}")" "$(dirname "$OUTPUT_FILE")"
        else
            rm -rf "${APKTOOL_DIR:?}/${OUTPUT_FILE//$WORK_DIR\/system\//}" "$OUTPUT_FILE"
        fi
    fi
}

BUILD_APEX()
{
    LOG "- Building ${1//$WORK_DIR/}"

    mkdir -p "$TMP_DIR/build/apk"
    cp -a "$TMP_DIR/original/META-INF" "$TMP_DIR/build/apk/META-INF"

    EVAL "apktool b -j \"$(nproc)\" \"$TMP_DIR\""

    mv -f "$TMP_DIR/dist/$(basename "$1")" "$1"
}

BUILD_PAYLOAD()
{
    LOG "- Building apex_payload.img"

    "$SRC_DIR/scripts/build_fs_image.sh" "ext4" --no-avb \
        -o "$TMP_DIR/unknown/apex_payload.img" -p "system" \
        "$TMP_DIR/unknown/apex_payload" "$TMP_DIR/unknown/file_context-apex_payload" "$TMP_DIR/unknown/fs_config-apex_payload" \
        > /dev/null
    rm -rf "$TMP_DIR/unknown/apex_payload" "$TMP_DIR/unknown/file_context-apex_payload" "$TMP_DIR/unknown/fs_config-apex_payload"
}

DECODE_APEX()
{
    LOG "- Decoding ${1//$WORK_DIR/}"
    EVAL "apktool d -j \"$(nproc)\" -o \"$TMP_DIR\" -r \"$1\""
}

DECODE_APK_IN_APEX()
{
    local INPUT_FILE="$1"
    local OUTPUT_FILE

    if [[ "$INPUT_FILE" == *"javalib"* ]]; then
        OUTPUT_FILE="$WORK_DIR/system/system/framework/$(basename "$INPUT_FILE")"
    else
        mkdir -p "$WORK_DIR/system/system/$(dirname "${INPUT_FILE/$TMP_DIR\/unknown\/apex_payload\//}")"
        OUTPUT_FILE="$WORK_DIR/system/system/${INPUT_FILE/$TMP_DIR\/unknown\/apex_payload\//}"
    fi

    if [ ! -f "$OUTPUT_FILE" ]; then
        mv -f "$INPUT_FILE" "$OUTPUT_FILE"
        LOG "- Decoding ${INPUT_FILE//$TMP_DIR\/unknown\//}"
        DECODE_APK "system" "${OUTPUT_FILE//$WORK_DIR\/system\//}" > /dev/null
    fi
}

EXTRACT_PAYLOAD()
{
    LOG_STEP_IN "- Unpacking apex_payload.img"

    if ! sudo -n -v &> /dev/null; then
        LOG "\033[0;33m! Asking user for sudo password\033[0m"
        if ! sudo -v 2> /dev/null; then
            ABORT "Root permissions are required to unpack APEX image"
        fi
    fi

    LOG_STEP_OUT

    mkdir -p "$TMP_DIR/unknown/apex_payload"
    mkdir -p "$TMP_DIR/tmp_out"
    EVAL "sudo mount -o
