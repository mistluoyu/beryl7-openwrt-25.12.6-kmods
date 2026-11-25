#!/usr/bin/env bash
# Offline build only. Never contacts a router or installs a package on it.
set -euo pipefail
[ "$#" -eq 2 ] || { echo "Usage: $0 INPUT_ARCHIVES NEW_WORK_DIR" >&2; exit 2; }
repo=$(cd "$(dirname "$0")" && pwd -P)
inputs=$(realpath "$1"); work=$(realpath -m "$2")
case "$work/" in "$repo/"*|*' '*) echo 'Use a new path outside this repository, without spaces.' >&2; exit 2;; esac
(cd "$inputs" && sha256sum -c "$repo/SOURCES.sha256")
umask 022
mkdir "$work"; cd "$work"; mkdir logs results
sdkname=openwrt-sdk-25.12.6-mediatek-filogic_gcc-14.3.0_musl.Linux-x86_64
rev=64900e756efa667774214f9c6b17c113222e01f7
sdk="$work/$sdkname"
tar --zstd -xf "$inputs/$sdkname.tar.zst"
for pkg in kernel/mac80211 kernel/mt76 libs/libnl-tiny; do
  tar -xzf "$inputs/openwrt-$rev.tar.gz" --strip-components=1 -C "$sdk" "openwrt-$rev/package/$pkg"
done
cp "$inputs"/{backports-6.18.55.tar.zst,mt76-2026.03.19~39c960c3.tar.zst,libnl-tiny-2025.12.02~40493a65.tar.zst,broadcom-wl-5.100.138.tar.bz2} "$sdk/dl/"
cd "$sdk"
cat >.config <<'CONFIG'
# CONFIG_ALL is not set
# CONFIG_ALL_NONSHARED is not set
# CONFIG_ALL_KMODS is not set
CONFIG_PACKAGE_libnl-tiny=m
CONFIG_PACKAGE_kmod-cfg80211=m
CONFIG_PACKAGE_kmod-mac80211=m
CONFIG_PACKAGE_MAC80211_MESH=y
CONFIG_PACKAGE_MAC80211_DEBUGFS=y
CONFIG_PACKAGE_kmod-mt76-core=m
CONFIG_PACKAGE_kmod-mt76-connac=m
CONFIG_PACKAGE_kmod-mt7996e=m
CONFIG
run() { local log=$1; shift; echo "== $log =="; if ! "$@" >"$work/logs/$log.log" 2>&1; then tail -40 "$work/logs/$log.log" >&2; return 1; fi; }
run config make defconfig
for s in kmod-mt7996e kmod-mac80211; do grep -Eq "^CONFIG_PACKAGE_$s=[ym]$" .config; done
j=${JOBS:-4}; run libnl make -j"$j" package/libs/libnl-tiny/compile V=s
run mac80211 make -j"$j" package/kernel/mac80211/compile V=s
run control make -j"$j" package/kernel/mt76/compile V=s
save() {
  local pkg=$1 variant=$2
  local a=(bin/targets/mediatek/filogic/packages/kmod-"$pkg"-[0-9]*.apk)
  [[ ${#a[@]} = 1 && -f ${a[0]} ]] || return 1
  mkdir -p "$work/results/$variant"
  cp "${a[0]}" "$work/results/$variant/"
}
save mac80211 control; save mt7996e control
run clean-mac make NO_DEPS=1 package/kernel/mac80211/clean V=s
cp "$repo/patches/484-wifi-mac80211-airtime.patch" package/kernel/mac80211/patches/subsys/
run airtime make -j"$j" NO_DEPS=1 package/kernel/mac80211/compile V=s
save mac80211 candidate
run clean-mt76 make NO_DEPS=1 package/kernel/mt76/clean V=s
cp "$repo/patches/999-mt7990-tx-rate.patch" package/kernel/mt76/patches/
run txrate make -j"$j" NO_DEPS=1 package/kernel/mt76/compile V=s
save mt7996e candidate
python3 "$repo/verify.py" "$sdk/staging_dir/host/bin/apk" "$work/results"
(cd "$work/results" && sha256sum {control,candidate}/*.apk > SHA256SUMS)
printf '%s\n' 'Research artifacts only; no installation or signing trust is implied.'
