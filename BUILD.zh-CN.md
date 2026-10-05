# 构建与安装

[English](BUILD.md)

需要 macOS、Xcode 与 iPhoneOS SDK、Python 3.9 或更新版本、自己购买的固定 macOS Steam 原版，以及自己的 Apple 开发签名和描述文件。脚本使用现代 Python 路径接口，需 Python 3.9+。`outputs/bigwalk-ios/source-audit.json` 固定原版哈希；其他版本应重新审计，不应关闭保护检查。

生成的键盘表包含本机 macOS 键盘布局数据，已从 Git 排除。准备桥接前，先在自己的 Mac 编译所附生成器。`BIGWALK_MAC_APP` 可覆盖标准 Steam 安装路径。原 `.app` 保持只读，生成的框架、清单和测试资源均在 `work/`。

以下从仓库根目录开始；先替换自己的团队和签名占位符，再执行 stage：

```sh
# Run from the repository root. Replace signing placeholders before staging.
python3 -m venv work/unity-tools
work/unity-tools/bin/python -m pip install UnityPy==1.25.4
export BIGWALK_MAC_APP="$HOME/Library/Application Support/Steam/steamapps/common/Big Walk/Big Walk.app"
export BIGWALK_TEAM_ID="YOUR_TEAM_ID"
export BIGWALK_SIGN_ID="YOUR_CODESIGN_IDENTITY"
cd outputs/bigwalk-ios
mkdir -p ../../work/bigwalk-probe
xcrun clang -fobjc-arc -framework Carbon -framework Foundation \
  compat/snapshot-keyboard.m -o ../../work/bigwalk-probe/snapshot-keyboard
../../work/bigwalk-probe/snapshot-keyboard compat/StrayUSKeyboard.inc \
  ../../work/bigwalk-probe/keyboard-reference.json
python3 prepare-unity.py
python3 tools/check-imports.py
xcodebuild -project BigWalkProbe.xcodeproj -scheme BigWalkProbe \
  -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath ../../work/bigwalk-probe/DerivedData \
  DEVELOPMENT_TEAM="$BIGWALK_TEAM_ID" -allowProvisioningUpdates build
python3 stage.py --identity "$BIGWALK_SIGN_ID" --steam-appid \
  --apple-controller --ios-audio-output --eos-device-auth \
  --eos-network-monitor --eos-menu-auth --mobile-texture-budget
codesign --verify --deep --strict ../../work/bigwalk-probe/package/BigWalkProbe.app
python3 tools/check-eos-candidate.py ../../work/bigwalk-probe/package/BigWalkProbe.app \
  --prepared ../../work/bigwalk-probe/Frameworks/GameAssembly.framework/GameAssembly.dylib \
  --audit ../../work/bigwalk-probe/eos-device-auth-audit.json \
  --output ../../work/bigwalk-probe/release-range-verification.json
```

## 签名与安装

在 Xcode 使用自己的团队。宿主申请 `com.apple.developer.kernel.increased-memory-limit`；可用性和实际内存上限取决于设备与签名描述文件。重新签名时保留匹配的 entitlement。代码保留稳定 bundle ID `dev.xzk.bigwalkprobe`；更新已有安装时保持相同 ID，以保留应用数据，不要为了更新先卸载。

从仓库根目录运行，将 `DEVICE_ID` 替换为已连接设备的 CoreDevice ID：

```sh
xcrun devicectl device install app --device DEVICE_ID work/bigwalk-probe/package/BigWalkProbe.app
xcrun devicectl device process launch --device DEVICE_ID dev.xzk.bigwalkprobe
```

完整已验证配置需要上述全部 stage 开关。默认 stage 仍关闭 EOS 实验且不会应用画质纹理预算；本发行配置未启用系统根证书实验。

## 可选诊断启动

停在主菜单，完成诊断后再进地图：

- `--probe-touch-keyboard`：回读原 Unity 的 W、Shift、Ctrl、鼠标左右键按住/松开，约 25 秒。
- `--probe-quality-presets`：启用昂贵变更测试六个原桌面画质档位，43 秒恢复原档位，采样共 90 秒。
- `--probe-mobile-resolutions`：切换四个自适应分辨率，再恢复此前保存的短边档位。

普通图标启动不会自动执行这些测试。日志及 JSON 写入 App Documents；原游戏会记录平台标识，应保留在本地。公开验证使用脱敏摘要，不上传 Documents 原始内容。

## 导出 IPA

签名验证后，将测试应用按 `Payload/BigWalkProbe.app` 结构打包，保留可执行权限和框架目录。导出供自己已注册的设备使用，仍受签名描述文件有效期限制；打包不能延长签名或增加可用设备。不要把含商业资源的 IPA 上传到本源码仓库。
