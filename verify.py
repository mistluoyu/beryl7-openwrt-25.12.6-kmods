"""Inspect locally built deflate-compressed APKv3 archives; never install them."""
import hashlib
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import zlib

apk, results = sys.argv[1:]
results = Path(results)
abi = 'kernel=6.12.112~f0a7348f9cb959e1bf4d0447669b031e-r1'
reference = {
    'mt7996e': ('c69e5d070c152ce9ba46cb8ea6e81a82eb1891e2889149ab5f610962126d3fa9',
                '6.12.112.2026.03.19~39c960c3-r3', {'kmod-hwmon-core', 'kmod-mac80211', 'kmod-mt76-connac', abi}),
    'mac80211': ('7e3004827656dbb706c95244e6f7b5d5e8cf68e73eb966037d4e8e6489741731',
                 '6.12.112.6.18.55-r2', {'hostapd-common', 'kmod-cfg80211', 'kmod-crypto-ccm', 'kmod-crypto-cmac', 'kmod-crypto-gcm', abi}),
}


def require(ok, message):
    if not ok:
        raise SystemExit(message)


def payload(path, name, version, deps):
    meta = subprocess.check_output([apk, 'adbdump', path], text=True)
    for field, value in [('name', f'kmod-{name}'), ('version', version), ('arch', 'aarch64_cortex-a53')]:
        require(f'  {field}: {value}' in meta.splitlines(), f'{name}: wrong {field}')
    dep_list = re.search(r'^  depends: [^\n]+\n((?:    - [^\n]+\n)+)', meta, re.M)
    require(dep_list and set(re.findall(r'    - (\S+)', dep_list[1])) == deps, f'{name}: dependencies differ')
    entry = re.search(r'^      - name: ' + re.escape(name + '.ko') + r'\n((?:        [^\n]*\n)+)', meta, re.M)
    digest = re.search(r'^        hash: ([0-9a-f]{64})$', entry[1], re.M) if entry else None
    require(digest, f'{name}: missing module hash')
    raw = path.read_bytes()
    require(raw[:4] == b'ADBd', 'Expected an APKv3 deflate archive')
    data = zlib.decompress(raw[4:], -15)
    require(data[:8] == b'ADB.pckg', 'Expected an APKv3 package')
    pos = 8
    while pos + 4 <= len(data):
        word, = struct.unpack_from('<I', data, pos)
        size = word & 0x3fffffff
        require(size >= 4 and pos + size <= len(data), 'Invalid block length')
        if word >> 30 == 2:
            block = data[pos + 12:pos + size]
            if hashlib.sha256(block).hexdigest() == digest[1]:
                return block, digest[1]
        pos += (size + 7) & ~7
    raise SystemExit(f'{name}: module payload missing or damaged')


def module_interface(path):
    info = subprocess.check_output(['readelf', '-p', '.modinfo', path], text=True)
    symbols = subprocess.check_output(['readelf', '-Ws', path], text=True)
    result = {m[1] for m in re.finditer(r'\]\s+((?:name|depends|vermagic)=[^\n]*)', info)}
    require(any(s.startswith('vermagic=') for s in result), 'Missing vermagic')
    for line in symbols.splitlines():
        f = line.split()
        if len(f) == 8 and (f[6] == 'UND' or f[7].startswith(('__ksymtab_', '__crc_'))):
            result.add(tuple(f[3:6] + [f[7]]))
    return result


with tempfile.TemporaryDirectory() as tmp:
    for name, (official, version, deps) in reference.items():
        interfaces = []
        for variant in ('control', 'candidate'):
            archive = results / variant / f'kmod-{name}-{version}.apk'
            block, digest = payload(archive, name, version, deps)
            require((digest == official) == (variant == 'control'), f'{variant}/{name}: unexpected module digest')
            path = Path(tmp) / (name + '.ko')
            path.write_bytes(block)
            interfaces.append(module_interface(path))
            print(variant, name, digest)
        require(interfaces[0] == interfaces[1], f'{name}: module interface differs; review before proceeding')
