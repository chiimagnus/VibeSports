#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Build a single Runner.usdz that contains 3 animation clips (Idle/SlowRun/FastRun),
without using Blender. This uses USD tools shipped on macOS (usdextract/usdcat/usdzip).

Usage:
  scripts/build_runner_usdz.sh \
    --idle "/path/to/Idle.usdz" \
    --slow "/path/to/Slow Run.usdz" \
    --fast "/path/to/Fast Run.usdz" \
    --out  "VibeSports/Resources/Runner/Runner.usdz" \
    [--default idle|slow|fast]

Notes:
  - Input USDZ must be the same character rig (e.g. Mixamo X Bot) and same skeleton.
  - Output USDZ is a single-file package (flattened) so it has no external dependencies.
EOF
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 1
  fi
}

idle=""
slow=""
fast=""
out=""
default_clip="idle"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --idle) idle="${2:-}"; shift 2 ;;
    --slow) slow="${2:-}"; shift 2 ;;
    --fast) fast="${2:-}"; shift 2 ;;
    --out) out="${2:-}"; shift 2 ;;
    --default) default_clip="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "${idle}" || -z "${slow}" || -z "${fast}" || -z "${out}" ]]; then
  usage
  exit 2
fi

need_cmd usdextract
need_cmd usdcat
need_cmd usdzip

if [[ ! -f "${idle}" ]]; then echo "File not found: ${idle}" >&2; exit 2; fi
if [[ ! -f "${slow}" ]]; then echo "File not found: ${slow}" >&2; exit 2; fi
if [[ ! -f "${fast}" ]]; then echo "File not found: ${fast}" >&2; exit 2; fi

out_dir="$(dirname "${out}")"
out_base="$(basename "${out}")"
mkdir -p "${out_dir}"
out="$(cd "${out_dir}" && pwd)/${out_base}"

workdir="$(mktemp -d "${TMPDIR:-/tmp}/vibesports-runner-usdz.XXXXXX")"
trap 'echo "Note: kept temporary workspace at ${workdir}" >&2' EXIT

extract_usdc() {
  local input_usdz="$1"
  local output_usdc="$2"

  local outdir="${workdir}/extract-$(basename "${output_usdc}" .usdc)"
  mkdir -p "${outdir}"
  usdextract -o "${outdir}" "${input_usdz}" >/dev/null

  local found
  found="$(find "${outdir}" -maxdepth 1 -type f -name '*.usdc' -print -quit)"
  if [[ -z "${found}" ]]; then
    echo "No .usdc found in extracted package: ${input_usdz}" >&2
    exit 3
  fi

  cp "${found}" "${workdir}/${output_usdc}"
}

extract_usdc "${idle}" "Idle.usdc"
extract_usdc "${slow}" "SlowRun.usdc"
extract_usdc "${fast}" "FastRun.usdc"

default_anim="Idle"
case "${default_clip}" in
  idle) default_anim="Idle" ;;
  slow) default_anim="SlowRun" ;;
  fast) default_anim="FastRun" ;;
  *)
    echo "Invalid --default value: ${default_clip} (expected: idle|slow|fast)" >&2
    exit 2
    ;;
esac

runner_usda="${workdir}/Runner.usda"
runner_usda_template="${workdir}/Runner.usda.template"
cat > "${runner_usda_template}" <<'USDA'
#usda 1.0
(
    defaultPrim = "Runner"
    metersPerUnit = 0.01
    upAxis = "Y"
    timeCodesPerSecond = 30
    startTimeCode = 0
    endTimeCode = 499
)

def Xform "Runner" (
    kind = "component"
    references = @Idle.usdc@</Idle>
)
{
    over SkelRoot "mixamorig_Hips"
    {
        over Skeleton "Skeleton"
        {
            rel skel:animationSource = </Runner/mixamorig_Hips/Skeleton/{{DEFAULT_ANIM}}>

            over SkelAnimation "Animation" (
                active = false
            )
            {
            }

            def SkelAnimation "Idle" (
                references = @Idle.usdc@</Idle/mixamorig_Hips/Skeleton/Animation>
            )
            {
            }

            def SkelAnimation "SlowRun" (
                references = @SlowRun.usdc@</Slow_Run/mixamorig_Hips/Skeleton/Animation>
            )
            {
            }

            def SkelAnimation "FastRun" (
                references = @FastRun.usdc@</Fast_Run/mixamorig_Hips/Skeleton/Animation>
            )
            {
            }
        }
    }
}
USDA

sed "s/{{DEFAULT_ANIM}}/${default_anim}/g" "${runner_usda_template}" > "${runner_usda}"

# Quick sanity: can we open the stage?
usdcat --loadOnly "${runner_usda}" >/dev/null

(
  cd "${workdir}"
  usdzip "${out}" "Runner.usda" "Idle.usdc" "SlowRun.usdc" "FastRun.usdc" >/dev/null
)

echo "OK: wrote ${out}"
