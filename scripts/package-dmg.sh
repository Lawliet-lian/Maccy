#!/bin/zsh

set -euo pipefail

# 这个脚本用于在本地快速生成可分发的 DMG。
# 它做了几件事：
# 1. 从工程配置中读取当前版本号和构建号；
# 2. 可选择直接复用现成的 Maccy.app，或者重新执行一次 xcodebuild；
# 3. 强制把产物里的 Info.plist 版本号同步成工程配置，避免构建缓存导致包内版本不一致；
# 4. 对生成的 app 重新做一次 ad-hoc 签名，确保修改过 Info.plist 后应用仍可打开；
# 5. 生成最终的 DMG 文件，方便本地安装或测试分发。

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROJECT_PATH="${PROJECT_ROOT}/Maccy.xcodeproj"
SCHEME_NAME="Maccy"
DEFAULT_CONFIGURATION="Debug"
DEFAULT_DERIVED_DATA="${HOME}/Library/Developer/Xcode/DerivedData/Maccy-packaging"
DEFAULT_OUTPUT_DIR="${PROJECT_ROOT}/dist"
DEFAULT_STAGE_DIR="${PROJECT_ROOT}/dist-dmg"

APP_PATH=""
CONFIGURATION="${DEFAULT_CONFIGURATION}"
DERIVED_DATA_PATH="${DEFAULT_DERIVED_DATA}"
OUTPUT_DIR="${DEFAULT_OUTPUT_DIR}"

usage() {
  cat <<'EOF'
用法：
  ./scripts/package-dmg.sh [--app PATH] [--configuration Debug|Release] [--derived-data PATH] [--output-dir PATH]

参数说明：
  --app PATH
      直接复用现成的 Maccy.app，不重新执行 xcodebuild。
      适合你已经在 Xcode 里编译成功，只想快速打包的场景。

  --configuration Debug|Release
      当没有传 --app 时，脚本会按这个配置执行构建。
      默认值是 Debug。

  --derived-data PATH
      自定义 xcodebuild 使用的 DerivedData 路径。
      默认值是 ~/Library/Developer/Xcode/DerivedData/Maccy-packaging

  --output-dir PATH
      最终 DMG 输出目录。
      默认值是 ./dist

示例：
  ./scripts/package-dmg.sh
  ./scripts/package-dmg.sh --configuration Release
  ./scripts/package-dmg.sh --app ~/Library/Developer/Xcode/DerivedData/.../Build/Products/Debug/Maccy.app
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="$2"
      shift 2
      ;;
    --configuration)
      CONFIGURATION="$2"
      shift 2
      ;;
    --derived-data)
      DERIVED_DATA_PATH="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      usage
      exit 1
      ;;
  esac
done

read_build_setting() {
  local key="$1"
  local value

  # 这里直接从工程文件里读取第一组匹配值。
  # 当前项目的 Debug/Release 在版本号上保持一致，所以用第一组即可。
  value="$(grep -E "^[[:space:]]*${key} = " "${PROJECT_PATH}/project.pbxproj" | head -n 1 | sed -E "s/.*${key} = ([^;]+);/\1/" | tr -d '"')"

  if [[ -z "${value}" ]]; then
    echo "无法从 project.pbxproj 读取 ${key}" >&2
    exit 1
  fi

  echo "${value}"
}

MARKETING_VERSION="$(read_build_setting "MARKETING_VERSION")"
CURRENT_PROJECT_VERSION="$(read_build_setting "CURRENT_PROJECT_VERSION")"

echo "项目根目录: ${PROJECT_ROOT}"
echo "目标版本号: ${MARKETING_VERSION}"
echo "目标构建号: ${CURRENT_PROJECT_VERSION}"

if [[ -z "${APP_PATH}" ]]; then
  echo "未传入现成 app，开始执行 xcodebuild (${CONFIGURATION})..."
  xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME_NAME}" \
    -configuration "${CONFIGURATION}" \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    clean build

  APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/Maccy.app"
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "找不到 Maccy.app: ${APP_PATH}" >&2
  exit 1
fi

INFO_PLIST="${APP_PATH}/Contents/Info.plist"
if [[ ! -f "${INFO_PLIST}" ]]; then
  echo "找不到 Info.plist: ${INFO_PLIST}" >&2
  exit 1
fi

# 强制把包内版本号同步成工程版本。
# 这样即使 DerivedData 中存在旧产物缓存，最终打出来的安装包版本信息也仍然准确。
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${MARKETING_VERSION}" "${INFO_PLIST}" \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${MARKETING_VERSION}" "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${CURRENT_PROJECT_VERSION}" "${INFO_PLIST}" \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${CURRENT_PROJECT_VERSION}" "${INFO_PLIST}"

# 修改过 Info.plist 后，重新做一次 ad-hoc 签名，避免包内签名失效。
codesign --force --deep --sign - "${APP_PATH}"

mkdir -p "${OUTPUT_DIR}"
rm -rf "${DEFAULT_STAGE_DIR}"
mkdir -p "${DEFAULT_STAGE_DIR}"

cp -R "${APP_PATH}" "${DEFAULT_STAGE_DIR}/"
ln -s /Applications "${DEFAULT_STAGE_DIR}/Applications"

DMG_PATH="${OUTPUT_DIR}/Maccy-${MARKETING_VERSION}.dmg"
rm -f "${DMG_PATH}"

hdiutil create \
  -volname "Maccy ${MARKETING_VERSION}" \
  -srcfolder "${DEFAULT_STAGE_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

echo ""
echo "打包完成"
echo "APP: ${APP_PATH}"
echo "DMG: ${DMG_PATH}"
