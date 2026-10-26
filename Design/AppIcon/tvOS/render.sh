#!/bin/bash
# Renders the Apple TV icon's layers into the app's brand assets: 1x, 2x and the App
# Store's size. The back layer, Sky, is opaque, as tvOS requires. Needs rsvg-convert
# (librsvg) and ffmpeg, for example from Homebrew.
set -euo pipefail

cd "$(dirname "$0")/../../.."
brand="SalahTV/Assets.xcassets/App Icon & Top Shelf Image.brandassets"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# render <svg> <width> <height> <png> <opaque|clear>
render() {
  if [[ "$5" == opaque ]]; then
    rsvg-convert -b none -w "$2" -h "$3" "$1" -o "$scratch/layer.png"
    ffmpeg -v error -y -i "$scratch/layer.png" -pix_fmt rgb24 "$4"
  else
    rsvg-convert -b none -w "$2" -h "$3" "$1" -o "$4"
  fi
}

for layer in sky texture glow mihrab crescent; do
  svg=(Design/AppIcon/tvOS/*-"$layer".svg)
  name="$(tr '[:lower:]' '[:upper:]' <<< "${layer:0:1}")${layer:1}"
  fill=clear
  [[ "$layer" == sky ]] && fill=opaque
  icon="$brand/App Icon.imagestack/$name.imagestacklayer/Content.imageset"
  store="$brand/App Icon - App Store.imagestack/$name.imagestacklayer/Content.imageset"
  render "${svg[0]}" 400 240 "$icon/$layer.png" "$fill"
  render "${svg[0]}" 800 480 "$icon/$layer@2x.png" "$fill"
  render "${svg[0]}" 1280 768 "$store/$layer.png" "$fill"
done
