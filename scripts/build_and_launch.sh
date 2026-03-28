#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/VibeSports.xcodeproj"
SCHEME="VibeSports"
DESTINATION="platform=macOS"
CONFIGURATION="Debug"
DERIVED_DATA_PATH="$ROOT_DIR/.build/DerivedData"

PRINT_USAGE=0
CLEAN=0
DO_LAUNCH=1
SCREENSHOT_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      PRINT_USAGE=1
      shift
      ;;
    --clean)
      CLEAN=1
      shift
      ;;
    --no-launch)
      DO_LAUNCH=0
      shift
      ;;
    --configuration)
      CONFIGURATION="${2:-}"
      shift 2
      ;;
    --derived-data)
      DERIVED_DATA_PATH="${2:-}"
      shift 2
      ;;
    --screenshot)
      SCREENSHOT_PATH="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown arg: $1" >&2
      PRINT_USAGE=1
      shift
      ;;
  esac
done

if [[ "$PRINT_USAGE" -eq 1 ]]; then
  cat <<EOF
Usage: $(basename "$0") [options]

Build (and optionally launch) the VibeSports macOS app via xcodebuild.

Options:
  --configuration Debug|Release   Build configuration (default: Debug)
  --derived-data PATH            DerivedData output path (default: ./.build/DerivedData)
  --clean                        Run 'xcodebuild clean' before build
  --no-launch                    Only build; do not open the app
  --screenshot PATH              Take a full-screen screenshot after launch
  -h, --help                     Show this help
EOF
  exit 0
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "Missing Xcode project: $PROJECT_PATH" >&2
  exit 1
fi

mkdir -p "$DERIVED_DATA_PATH"

common_args=(
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -destination "$DESTINATION"
  -configuration "$CONFIGURATION"
  -derivedDataPath "$DERIVED_DATA_PATH"
)

if [[ "$CLEAN" -eq 1 ]]; then
  xcodebuild "${common_args[@]}" clean
fi

xcodebuild "${common_args[@]}" build

products_dir="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION"
app_path="$products_dir/$SCHEME.app"
if [[ ! -d "$app_path" ]]; then
  app_path="$(/usr/bin/find "$products_dir" -maxdepth 1 -name '*.app' -print -quit || true)"
fi

if [[ -z "$app_path" || ! -d "$app_path" ]]; then
  echo "Failed to locate built .app under: $products_dir" >&2
  exit 2
fi

echo "Built app: $app_path"

if [[ "$DO_LAUNCH" -eq 1 ]]; then
  /usr/bin/open -n "$app_path"
fi

if [[ -n "$SCREENSHOT_PATH" ]]; then
  /bin/sleep 2
  if /usr/sbin/screencapture -x "$SCREENSHOT_PATH"; then
    echo "Screenshot: $SCREENSHOT_PATH"
  else
    echo "Warning: screencapture failed (no active display?)." >&2
  fi
fi
