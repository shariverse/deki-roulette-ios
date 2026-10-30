#!/bin/bash
#
# App Store 用スクリーンショットを、1 つの表示サイズについて言語ごとに撮る。
# UI テスト（AppStoreScreenshotTests）を流し、撮った画像を出力先に書き出す。
# ステータスバーは 9:41・電池満タンにそろえる（iOS の Simulator のみ。visionOS にはステータスバーが無い）。
#
# 使い方:
#   scripts/app-store-screenshots.sh <表示サイズ> [言語（カンマ区切り）]
#   scripts/app-store-screenshots.sh APP_IPHONE_67           # docs/app-store/languages.json の全言語
#   scripts/app-store-screenshots.sh APP_APPLE_VISION_PRO ja
#
# 表示サイズ・機種・プラットフォームは docs/app-store/screenshots.json、言語は docs/app-store/languages.json で決める。
# 機種は screenshots.json の devices のうち、ランナーにある最初のものを、SDK 以下でいちばん新しいランタイムで新しく作る。
# 1 回ビルドしたもの（build-for-testing）を言語ごとに使い回す。
#
# 撮り方はプラットフォームで違う。
#   iOS      XCTest の添付（XCUIScreen.main.screenshot()）をテストが付け、xcresult から書き出す
#   visionOS XCTest の手動スクリーンショットが使えない（1×1 の絵になる）ため、テストが runner の Documents に置く
#            合図（capture-*.request）を見て、ホスト側で `xcrun simctl io ... screenshot` で撮る。テストは合図が消えるまで待つ
#
# 出力先: $SCREENSHOTS_DIR/<表示サイズ>/<言語>/（画像。iOS は manifest.json も。既定は build/app-store-screenshots）
#
# 環境変数:
#   SCREENSHOTS_DIR  出力先（既定は build/app-store-screenshots）
#   XCODEBUILD       xcodebuild の代わりに使うコマンド（既定は xcodebuild）。空白で区切って引数も渡せる（~ は展開しないので $HOME を使う）。
#                    テストは手元の Simulator で流す前提なので、別の Mac で流すラッパーは使わない
#
set -euo pipefail

cd "$(dirname "$0")/.."

DISPLAY_TYPE="${1:?表示サイズ（例: APP_IPHONE_67）を指定してください}"
LANGUAGES="${2:-}"

SCREENSHOTS_DIR="${SCREENSHOTS_DIR:-build/app-store-screenshots}"
SCREENSHOTS_JSON=docs/app-store/screenshots.json
LANGUAGES_JSON=docs/app-store/languages.json
PROJECT=DekiRoulette.xcodeproj
SCHEME=DekiRouletteScreenshots
read -r -a XCODEBUILD_COMMAND <<<"${XCODEBUILD:-xcodebuild}"

if ! jq -e --arg type "$DISPLAY_TYPE" '.displayTypes[$type]' "$SCREENSHOTS_JSON" >/dev/null; then
  echo "表示サイズ ${DISPLAY_TYPE} は ${SCREENSHOTS_JSON} にありません" >&2
  exit 1
fi
EXPECTED_SCREENSHOTS=$(jq -r '.screenshotCount' "$SCREENSHOTS_JSON")
EXPECTED_SIZES=$(jq -r --arg type "$DISPLAY_TYPE" '.displayTypes[$type].sizes | join(" ")' "$SCREENSHOTS_JSON")
PLATFORM=$(jq -r --arg type "$DISPLAY_TYPE" '.displayTypes[$type].platform // "iOS"' "$SCREENSHOTS_JSON")

# 言語の一覧（language appleLanguage appleLocale をタブ区切り）。指定が無ければ全言語、指定に無い言語があれば止まる
LANGUAGE_LIST=$(jq -r --arg wanted "$LANGUAGES" '
  ($wanted | split(",") | map(select(. != ""))) as $w
  | .languages
  | if ($w | length) == 0 then . else
      (map(.language) as $known | ($w - $known)) as $unknown
      | if ($unknown | length) > 0 then error("languages.json に無い言語: \($unknown | join(","))") else . end
      | map(select(.language as $l | $w | index($l)))
    end
  | .[] | [.language, .appleLanguage, .appleLocale] | @tsv' "$LANGUAGES_JSON")

case "$PLATFORM" in
  iOS)
    SDK_NAME=iphonesimulator
    RUNTIME_MATCH=SimRuntime.iOS
    DESTINATION_PLATFORM=iOS
    ;;
  visionOS)
    SDK_NAME=xrsimulator
    RUNTIME_MATCH=SimRuntime.xrOS
    DESTINATION_PLATFORM=visionOS
    ;;
  *)
    echo "${SCREENSHOTS_JSON} の platform は iOS か visionOS にしてください（${DISPLAY_TYPE}: ${PLATFORM}）" >&2
    exit 1
    ;;
esac

# 言語ごとにアプリを消してから流すための Bundle ID（project.yml の最初の PRODUCT_BUNDLE_IDENTIFIER = アプリ本体）
APP_BUNDLE_ID=$(sed -n 's/^ *PRODUCT_BUNDLE_IDENTIFIER: *//p' project.yml | head -n 1 | tr -d '[:space:]')

WORK_DIR=$(mktemp -d)
UDID=""

# 途中で失敗しても、作った Simulator と作業用のディレクトリを消す
cleanup() {
  if [[ -n "$UDID" ]]; then
    xcrun simctl shutdown "$UDID" 2>/dev/null || true
    xcrun simctl delete "$UDID" 2>/dev/null || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# MARK: - Simulator

SDK_VERSION=$(xcrun --sdk "$SDK_NAME" --show-sdk-version)

# ビルドに使う SDK より新しいランタイム（ベータなど）には入れられないので、SDK 以下でいちばん新しいものを使う
latest_runtime() {
  xcrun simctl list -j runtimes | jq -r --arg sdk "$SDK_VERSION" --arg match "$RUNTIME_MATCH" '
    def ver: split(".") | map(tonumber);
    [.runtimes[] | select(.isAvailable and (.identifier | contains($match)))
      | select((.version | ver)[:2] <= ($sdk | ver)[:2])]
    | sort_by(.version | ver) | last | .identifier // empty'
}

RUNTIME_ID=$(latest_runtime)
if [[ -z "$RUNTIME_ID" ]]; then
  echo "${PLATFORM} ${SDK_VERSION} 以下のランタイムが無いのでダウンロードします"
  xcodebuild -downloadPlatform "$PLATFORM"
  RUNTIME_ID=$(latest_runtime)
fi
# macOS の bash 3.2 は、変数名の直後に全角文字が続くと変数名の一部と見なすことがあるので、必ず波括弧で閉じる
echo "ランタイム: ${RUNTIME_ID}（SDK ${SDK_VERSION}）"

DEVICE_NAME=""
while IFS= read -r -u 3 candidate; do
  device_type=$(xcrun simctl list -j devicetypes | jq -r --arg name "$candidate" '.devicetypes[] | select(.name == $name) | .identifier' | head -n 1)
  if [[ -n "$device_type" ]] && UDID=$(xcrun simctl create "DekiRoulette-Screenshot-${DISPLAY_TYPE}" "$device_type" "$RUNTIME_ID" 2>/dev/null); then
    DEVICE_NAME="$candidate"
    break
  fi
  UDID=""
done 3< <(jq -r --arg type "$DISPLAY_TYPE" '.displayTypes[$type].devices[]' "$SCREENSHOTS_JSON")

if [[ -z "$UDID" ]]; then
  echo "${DISPLAY_TYPE} の Simulator を作れませんでした。${SCREENSHOTS_JSON} の devices を見直してください" >&2
  xcrun simctl list devicetypes >&2 || true
  exit 1
fi
echo "機種: ${DEVICE_NAME}（${UDID}）"

boot() {
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null
  # ステータスバーと外観の設定は iOS の Simulator にだけある
  if [[ "$PLATFORM" == iOS ]]; then
    xcrun simctl ui "$UDID" appearance light
    xcrun simctl status_bar "$UDID" override \
      --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
      --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
  fi
}

# iPad のステータスバーには日付も出る。日付は Simulator 全体の言語・地域に従うので、言語ごとに設定して起動し直す
set_device_language() {
  xcrun simctl spawn "$UDID" defaults write -g AppleLanguages -array "$1"
  xcrun simctl spawn "$UDID" defaults write -g AppleLocale -string "$2"
  xcrun simctl shutdown "$UDID"
  boot
}

# MARK: - ビルド

if [[ ! -d "$PROJECT" ]]; then
  echo "xcodegen generate"
  xcodegen generate
fi

# Simulator を起動したままビルドすると、非力なランナーが固まることがあるので、ビルドしてから起動する
DERIVED_DATA="$WORK_DIR/DerivedData"
"${XCODEBUILD_COMMAND[@]}" build-for-testing \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=${DESTINATION_PLATFORM} Simulator,id=${UDID}" \
  -derivedDataPath "$DERIVED_DATA" \
  -quiet
boot

# MARK: - 撮影

run_tests() {
  TEST_RUNNER_APP_STORE_SCREENSHOTS=1 \
    TEST_RUNNER_APP_STORE_LANGUAGE="$2" \
    TEST_RUNNER_APP_STORE_LOCALE="$3" \
    "${XCODEBUILD_COMMAND[@]}" test-without-building \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=${DESTINATION_PLATFORM} Simulator,id=${UDID}" \
    -derivedDataPath "$DERIVED_DATA" \
    -only-testing:DekiRouletteUITests/AppStoreScreenshotTests \
    -resultBundlePath "$1"
}

# iOS: テストを流し、テストが付けた添付（画面の画像）を xcresult から $4 に書き出す
capture_ios() {
  rm -rf "$1"
  run_tests "$1" "$2" "$3" || return 1
  rm -rf "${4:?}"
  mkdir -p "$4"
  xcrun xcresulttool export attachments --path "$1" --output-path "$4"
}

# simctl のスクリーンショットを最大 15 秒で撮る。ほかの simctl と競合して固まることがあるので、長すぎたら打ち切る
# （打ち切ったときは合図を消さないので、次の周で撮り直す。途中の PNG は消してから撮る）
capture_screenshot() {
  local name="$1" destination="$2"
  rm -f "$destination/$name.png"
  xcrun simctl io "$UDID" screenshot "$destination/$name.png" >/dev/null 2>&1 &
  local shot_pid=$!
  (sleep 15; kill -9 "$shot_pid" 2>/dev/null) &
  local watchdog_pid=$!
  if wait "$shot_pid"; then
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
    return 0
  fi
  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
  rm -f "$destination/$name.png"
  return 1
}

# visionOS: テストを裏で流し、合図（capture-*.request）を見つけたら simctl で撮る。テストは合図が消えるまで待つ。
# 合図は runner（テストを載せたアプリ）の Documents に置かれ、アプリを入れ直すたびにコンテナの場所（UUID）が変わるので、
# 決め打ちせず、Simulator のコンテナ置き場を毎回探す。探すのと撮るのを分けているのは、撮影が固まったときに探し続けるため
capture_vision_os() {
  local result="$1" language="$2" locale="$3" destination="$4"
  rm -rf "$result"
  rm -rf "${destination:?}"
  mkdir -p "$destination"

  local containers="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Containers/Data/Application"
  # 前の実行が残した合図を先に片付ける（古い画面のまま撮ってしまわないよう）
  find "$containers" -maxdepth 3 -name 'capture-*.request' -delete 2>/dev/null || true

  local log="$WORK_DIR/test-${language}.log"
  TEST_RUNNER_APP_STORE_SCREENSHOTS=1 \
    TEST_RUNNER_APP_STORE_LANGUAGE="$language" \
    TEST_RUNNER_APP_STORE_LOCALE="$locale" \
    "${XCODEBUILD_COMMAND[@]}" test-without-building \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=${DESTINATION_PLATFORM} Simulator,id=${UDID}" \
    -derivedDataPath "$DERIVED_DATA" \
    -only-testing:DekiRouletteUITests/AppStoreScreenshotTests \
    -resultBundlePath "$result" >"$log" 2>&1 &
  local test_pid=$!

  local request name
  while kill -0 "$test_pid" 2>/dev/null; do
    while IFS= read -r request; do
      name=$(basename "$request" .request)
      name=${name#capture-}
      if capture_screenshot "$name" "$destination"; then
        echo "    撮影: $name"
        rm -f "$request"
      else
        echo "    撮影できない（次の周でやり直す）: $name" >&2
      fi
    done < <(find "$containers" -maxdepth 3 -name 'capture-*.request' 2>/dev/null | sort)
    sleep 0.3
  done
  # テストが途中で落ちたときの合図は片付ける（違う画面のまま撮ってしまわないよう）
  find "$containers" -maxdepth 3 -name 'capture-*.request' -delete 2>/dev/null || true

  if ! wait "$test_pid"; then
    echo "${DISPLAY_TYPE} / ${language} のテストが失敗しました。${log} の末尾:" >&2
    tail -30 "$log" >&2
    return 1
  fi
}

while IFS=$'\t' read -r -u 3 language apple_language apple_locale; do
  echo "==> ${DISPLAY_TYPE} / ${language}"
  if [[ "$DISPLAY_TYPE" == APP_IPAD* ]]; then
    set_device_language "$apple_language" "$apple_locale"
  fi

  # 前回の実行の項目リスト（UserDefaults）と起動直後のスナップショットが写らないよう、言語ごとに消してから流す
  xcrun simctl uninstall "$UDID" "$APP_BUNDLE_ID" 2>/dev/null || true

  # CI の Simulator は、スクリーンショットの取得がタイムアウトすることがあるので、1 回だけやり直す
  result="$WORK_DIR/${language}.xcresult"
  destination="$SCREENSHOTS_DIR/$DISPLAY_TYPE/$language"
  if [[ "$PLATFORM" == visionOS ]]; then
    capture_attempt() { capture_vision_os "$result" "$apple_language" "$apple_locale" "$destination"; }
  else
    capture_attempt() { capture_ios "$result" "$apple_language" "$apple_locale" "$destination"; }
  fi
  if ! capture_attempt; then
    echo "::warning::${DISPLAY_TYPE} / ${language} の撮影に失敗したので、やり直します"
    capture_attempt
  fi

  # テストが飛ばされた（環境変数が渡らなかった）ときも xcodebuild は成功で終わるので、撮れた枚数を確かめる。
  # App Store Connect は寸法が 1px でも違えば弾くので、撮った時点で寸法も確かめる
  count=0
  for image in "$destination"/*.png; do
    [[ -e "$image" ]] || continue
    count=$((count + 1))
    size=$(sips -g pixelWidth -g pixelHeight "$image" | awk '/pixelWidth/ { w = $2 } /pixelHeight/ { h = $2 } END { print w "x" h }')
    if [[ " $EXPECTED_SIZES " != *" $size "* ]]; then
      echo "$(basename "$image") の寸法が ${size} でした（${EXPECTED_SIZES} のどれかのはず）" >&2
      exit 1
    fi
  done
  if [[ "$count" -ne "$EXPECTED_SCREENSHOTS" ]]; then
    echo "${DISPLAY_TYPE} / ${language} のスクリーンショットが ${count} 枚でした（${EXPECTED_SCREENSHOTS} 枚のはず）。テストが飛ばされていないか確かめてください" >&2
    exit 1
  fi
  echo "    ${destination} に ${count} 枚を書き出しました"
done 3< <(printf '%s\n' "$LANGUAGE_LIST")
