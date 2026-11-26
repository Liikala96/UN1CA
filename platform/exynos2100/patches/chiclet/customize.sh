KERNEL_API_URL="https://api.github.com/repos/FlopKernel-Series/flop_exynos2100_kernel/releases/latest"

AUTH_ARGS=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    AUTH_ARGS=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi

KERNEL_JSON="$(curl -fsSL \
    "${AUTH_ARGS[@]}" \
    -H "Accept: application/vnd.github+json" \
    "$KERNEL_API_URL")"

LATEST_TAG="$(
    printf '%s\n' "$KERNEL_JSON" \
    | grep -m1 '"tag_name"' \
    | cut -d '"' -f4
)"
if [[ -z "$LATEST_TAG" ]]; then
    LOGE "Failed to resolve latest release tag for FlopKernel-Series/flop_exynos2100_kernel"
    exit 1
fi

KERNEL_DL_BASE="https://github.com/FlopKernel-Series/flop_exynos2100_kernel/releases/download/$LATEST_TAG"

LOG_STEP_IN "- Downloading FloppyKernel ($LATEST_TAG) Vanilla variant"
if [[ -d "$TMP_DIR" ]]; then
    EVAL "rm -rf \"$TMP_DIR\""
fi
mkdir -p "$TMP_DIR"

KERNEL_ARCHIVE="$(
    printf '%s\n' "$KERNEL_JSON" \
    | grep -oE '"name"[[:space:]]*:[[:space:]]*"Floppy_[^"]*-Vanilla-exynos2100-[^"]*\.zip"' \
    | cut -d '"' -f4 \
    | sort -u \
    | tail -n 1
)"

if [[ -z "$KERNEL_ARCHIVE" ]]; then
    LOGE "No matching FloppyKernel Vanilla zip found in tag '$LATEST_TAG'"
    exit 1
fi

DOWNLOAD_FILE "$KERNEL_DL_BASE/$KERNEL_ARCHIVE" "$TMP_DIR/$KERNEL_ARCHIVE"

mkdir -p "$TMP_DIR/extracted"
EVAL "unzip -o \"$TMP_DIR/$KERNEL_ARCHIVE\" -d \"$TMP_DIR/extracted\""

for i in "boot" "dtbo" "vendor_boot"; do
    LOG "- Replacing $i.img"

    # Először a készülékspecifikus (pl. o1s) mappában keresi, ha nincs, akkor bárhol a ZIP-ben
    SRC_IMG="$(find "$TMP_DIR/extracted" -type f -path "*${TARGET_CODENAME}*" -name "$i.img" | head -n 1)"
    if [[ -z "$SRC_IMG" ]]; then
        SRC_IMG="$(find "$TMP_DIR/extracted" -type f -name "$i.img" | head -n 1)"
    fi

    if [[ -z "$SRC_IMG" ]]; then
        LOGE "Could not find '$i.img' inside '$KERNEL_ARCHIVE' (archive structure might be AnyKernel3 Image.gz/dtb)"
        exit 1
    fi

    if [[ -f "$WORK_DIR/kernel/$i.img" ]]; then
        EVAL "rm -f \"$WORK_DIR/kernel/$i.img\""
    fi

    EVAL "mv \"$SRC_IMG\" \"$WORK_DIR/kernel/$i.img\""
done

EVAL "rm -rf \"$TMP_DIR\""

LOG_STEP_OUT

unset AUTH_ARGS KERNEL_ARCHIVE KERNEL_API_URL KERNEL_DL_BASE KERNEL_JSON LATEST_TAG SRC_IMG
