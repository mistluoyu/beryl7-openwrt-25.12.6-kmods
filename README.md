# Beryl 7 / MT7990: TX rate 与 airtime 最小回移实验

只针对官方 OpenWrt **25.12.6、mediatek/filogic、GL-MT3600BE**。用原版 SDK 构建两个内核模块软件包，不编译或刷写内核镜像，不改固件、WED 或 AQL 阈值。本仓库没有安装器。不同发行版、内核 ABI 或无线 backports 请重新审查，不要复用包。

## 别人怎么做、这里取哪部分

- [社区 107（固定源码）](https://github.com/plcharriere/gl-mt3600be-openwrt/blob/92b668321f968b3bfe3b6a1de23317fe0f3f52ad/package/kernel/mt76/patches/107-mt7996-take-MT7990-TX-rate-from-firmware-report.patch)：从固件报告维护每站真实 TX rate，避免固定低速帧的 TX status 覆盖缓存。这里的 `999` 是该补丁的发行源码上下文适配，序号用于本地应用顺序，不是另一个上游变更。MediaTek 的上报实现是来源参考，不等于本仓库引入了其 SDK。对应的 [mt76 #1043](https://github.com/openwrt/mt76/issues/1043) 是另一设备的问题报告，不是合并记录或本机验证。
- [社区 925](https://github.com/plcharriere/gl-mt3600be-openwrt/blob/0a6263c70494bb8f5337c46d8400cd3cde6f0505/package/kernel/mac80211/patches/subsys/925-wifi-mac80211-don-t-estimate-airtime-for-unsupported.patch) 与 107 同见于 `beryl7-2026-10-15`、`-10-24`、`-11-02`。本仓库取 [OpenWrt 主线的 484](https://github.com/openwrt/openwrt/commit/6432c1db26e56eeea48b8541abdb18683d9b34e9)（[PR #26397](https://github.com/openwrt/openwrt/pull/26397)）：同一 wireless-next 提交 `f394cbd0980c95c9173f8551a5eb4c4f28d598eb`。在官方发行 recipe 准备好的 `net/mac80211/airtime.c` 上，两者分别以 `patch --fuzz=0 -p1` 应用；源码 SHA256 均从 `718be20db29dfecead18d469ebb094a82c44a18dc640f3534c35dd003df76d53` 变为 `802f91c905beafed13554829da9540c3373cc17feb6b64953e2adc2f8f7a1e37`。不要叠加两份。官方 v25.12.6 原文件缺少这两个保护。
- [社区较新的固定树](https://github.com/plcharriere/gl-mt3600be-openwrt/tree/92b668321f968b3bfe3b6a1de23317fe0f3f52ad/package/kernel/mac80211/patches/subsys) 换到 backports 7.2 后仍有 **484**（且 mt76 同时有 107、900）。其 484 的补丁头和两个实际改动均已核对，在 25.12.6 上也得到同一结果。不能根据 `925` 文件名不在新树里就说社区不再修 airtime。
- 107 可上报 HE 106-tone RU；旧 airtime 估算器不支持该宽度。484 拒绝不支持的宽度，并在 duration 无效时不读未初始化的 overhead。普通 160 MHz 仍可估算。**这不是为所有包提高估算值或放大队列**，也不是 107 的编译先决条件。
- [社区 900 / WTBL airtime](https://github.com/openwrt/openwrt/pull/26037)：处理硬件计数器重置造成的错误差值，针对已消耗的 airtime、公平调度；不恢复 6 Mbps 的速率缓存。10-15 的发行补丁树已有 107+925、无该 900 文件。此实验不带 900，不改变公平调度策略。

## 在 Linux x86-64 上复核

使用非 root 用户和区分大小写的文件系统。需要常用 OpenWrt SDK 构建依赖，包括 GNU make、gcc/g++、gawk、rsync、tar、zstd、patch、binutils、Python 3。不要在共享仓库目录里解 SDK。将 `SOURCES.sha256` 的六个具名输入放在同一目录：

1. [官方 SDK 及 SHA256 清单](https://downloads.openwrt.org/releases/25.12.6/targets/mediatek/filogic/)。另行核对发行签名；本仓库中的哈希不替代对发布者的信任。
2. [官方 release 源码快照](https://codeload.github.com/openwrt/openwrt/tar.gz/64900e756efa667774214f9c6b17c113222e01f7)，保存为 `SOURCES.sha256` 中的 `openwrt-<commit>.tar.gz`。
3. 依清单文件名从 [OpenWrt 源码缓存](https://sources.openwrt.org/) 获取 backports、mt76、libnl-tiny、broadcom-wl。Broadcom 包是这个 mac80211 recipe 的构建输入，不是给 MT7990 换固件。

```sh
./build.sh ../inputs ../work-new
# 或只重新验证已生成结果：
python3 verify.py ../work-new/openwrt-sdk-25.12.6-mediatek-filogic_gcc-14.3.0_musl.Linux-x86_64/staging_dir/host/bin/apk ../work-new/results
```

`work-new` 必须不存在，`JOBS` 可选。构建顺序：发行配置的两个对照包 → 只改 airtime 的 mac80211 → 在相同 mac80211 上构建带 107 的 mt7996e。构建系统可能编译额外模块，`results/` 仅保留两对研究包，**不是安装清单**。不分发 SDK 密钥、日志、生成包、`.git` 或设备信息。

`verify.py` 对照官方发行 APK 内的模块 SHA256，检查候选与对照的依赖列表、内核 ABI 依赖、架构、包版本、实际 ELF 字节、vermagic、导入与导出符号名。若不匹配则退出，不是强行放行。文件名/包版本沿用对照以作研究，目录和模块哈希区分候选；**包不是官方签发，校验成功不等于签名可信、全面 ABI 兼容或可安全加载**。不修改签名或 ABI 检查。升级 OpenWrt 后以新版本为基线重新审查。

## 验证设计（不自动执行）

条件固定：WED 关闭、默认 AQL、同一 5 GHz/160 MHz 非 MLO 客户端和同一有线源；三组分别为官方原版、仅 484、484+107。每轮统一重新关联并先暖机，以免把一次重关联清缓存误认为修复；再经历空闲→串流→再次串流，多轮对比。记录 `iw` TX rate 的时间序列、AP 下行字节增量、AQL pending、VD Networking 中位数/P95 与丢帧。不以 LuCI 瞬时数字单独验收。保留有线管理与可信官方恢复路径；无受信任的部署和回滚方案前不上机。若只修正显示而默认 AQL 下的吞吐/时延未恢复，不把问题标为解决。

## SDK 对照与 Beryl 7 实机结果

| `.ko` | 无改动 control SHA256（与官方发布包字节相同） | 本次双补丁候选 SHA256 |
|---|---|---|
| `mt7996e.ko` | `c69e5d070c152ce9ba46cb8ea6e81a82eb1891e2889149ab5f610962126d3fa9` | `4c33e443831e47b048c7eb0cd48b73c012f5b1d448967f209d68ed3b8654d4be` |
| `mac80211.ko` | `7e3004827656dbb706c95244e6f7b5d5e8cf68e73eb966037d4e8e6489741731` | `beecac4e2adf5764b09baedee66ca470e715e7dc54ddc0c122684c26bb0b1613` |

本表比对 APK 内的实际模块，不要求 APK 容器或签名相同。包元数据和 ELF 静态检查已通过。Beryl 7 实机在 5 GHz / 160 MHz、非 MLO、WED 关闭、默认 BE AQL 5/12 ms 下，以 Virtual Desktop 固定 200 Mbps 对比：仅 484 时 AP 下行约 103 Mbps，短窗口 TX rate 全为 6 Mbps，Networking 约 110 ms；484 + 107 时 AP 下行稳定段约 208 Mbps、驱动速率约 1.44–2.40 Gbps、Networking 约 4 ms，随后实际游戏正常。这只验证了双补丁组合，不证明 107 单独适用于所有客户端。

## 下载与安装签名包

**仅适用 GL.iNet Beryl 7（GL-MT3600BE）、官方 OpenWrt 25.12.6 `mediatek/filogic`、`aarch64_cortex-a53`、内核依赖 `6.12.112~f0a7348f9cb959e1bf4d0447669b031e-r1`。** 不要给其他机型、其他发行版或其他内核 ABI 安装。安装前保留有线管理，确认已备份配置和同版本官方两个模块包及签名仓库索引，先结束串流。不要卸载正在运行的 Wi-Fi 模块来切换。

1. 从本仓库 Releases 或默认分支成功的手动 Actions 构建下载两个**已签名**的 APK、`SHA256SUMS` 和项目公钥 `beryl7-release.pem`。常规 CI 的 `unsigned-kmods` 不用于安装。项目不是 OpenWrt 官方发布。
2. **通过独立可信渠道核对公钥指纹**。下面的指纹是公钥 SPKI DER 的 SHA256，不是 PEM 文本的 SHA256。在安装电脑上执行：

   ```sh
   openssl pkey -pubin -in beryl7-release.pem -outform DER | sha256sum
   ```

   项目公钥指纹：`ac1e66171d5e201336739c1761c3585f1666075ecd11fe051d6a75e381f787aa`。

3. 把上述四个文件传到路由器的专用临时目录（示例为 `/tmp/beryl7-install`），登录路由器，核对机型、系统和 ABI：

   ```sh
   cat /tmp/sysinfo/board_name
   cat /etc/openwrt_release
   uname -r
   apk --no-network --repositories-file /dev/null list --installed kernel
   ```

4. 先验签和模拟；只有命令成功且模拟仅替换这两个包，才执行安装及重启（所有 Wi-Fi 都会临时断开）。`--force-reinstall` 只用于替换与官方同版本号的包，不跳过签名或依赖检查。

   ```sh
   cd /tmp/beryl7-install
   sha256sum -c SHA256SUMS
   mkdir -p keys
   cp beryl7-release.pem keys/
   set -- ./kmod-mac80211-*.apk ./kmod-mt7996e-*.apk
   apk --no-network --keys-dir "$PWD/keys" verify "$@"
   apk --no-network --keys-dir "$PWD/keys" --repositories-file /dev/null \
       add --simulate --force-reinstall "$@"
   ```

   ```sh
   # 确认上面的模拟结果后，在同一 shell 执行：
   apk --no-network --keys-dir "$PWD/keys" --repositories-file /dev/null \
       add --force-reinstall "$@" && reboot
   ```

公钥只用于这次 APK 命令，不需要永久加入 `/etc/apk/keys`。不要用 `--allow-untrusted` 或 `--force-broken-world` 绕过错误。重启后确认三个 BSS、5 GHz 频道和串流表现。保留默认 AQL；本修复不要求 WED，也不自动改变任何路由器配置。

### 回到官方版本

使用预先下载并验签的 **25.12.6 / 同内核 ABI** 官方仓库索引与对应两个官方 APK。由于版本号相同，必须用官方仓库索引里的包身份（`name><Q1…`）定向选择，不能只用包名重装。官方索引可通过系统自带 OpenWrt 公钥验签。先用 `apk add --simulate --force-reinstall` 核实只替换两包，再执行并重启。升级固件前先恢复官方包、解除旧 ABI 的本地固定，升级后按新版本重新核对。

## GitHub Actions

推送和 Pull Request 只运行无密钥的构建验证；在默认分支手动运行 `Build OpenWrt 25.12.6 kmods` 则生成 `beryl7-openwrt-25.12.6-signed-kmods`，含两个签名 APK、公钥和 `SHA256SUMS`。在上传前，构建会比较原版对照并验证两包签名、依赖和模块接口。工作流不部署路由器。

维护者应将项目签名私钥配置为受限环境 `release-signing` 的 **环境 Secret** `BERYL7_RELEASE_PRIVATE_PEM`，环境仅允许默认分支。不要把私钥复制进仓库、日志或 artifact。离线流程使用同一个 `build.sh`：传入 `APK_SIGN_KEY` 指向受保护的、临时解密的 PEM 文件；脚本先核对它与已提交公钥匹配，再为候选包签名。不要把加密私钥的解锁凭据和备份存一起。
