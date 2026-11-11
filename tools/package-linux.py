#!/usr/bin/env python3
"""把已有的 Linux x64 构建产物打成 Debian 和 Arch 安装包。"""

import argparse
import gzip
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

PROJECT = Path(__file__).resolve().parent.parent
NAME = 'shiyi-translator'
URL = 'https://github.com/leychan/shiyi-translator'
MAINTAINER = 'leychan <leychan_@outlook.com>'


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def glibc_requirement(bundle):
    versions = set()
    for file in bundle.rglob('*'):
        if file.is_file() and (file.suffix == '.so' or '.so.' in file.name or file.name == 'just_translator'):
            info = run('readelf', '--version-info', str(file), capture_output=True, text=True)
            versions.update(re.findall(r'GLIBC_(\d+\.\d+)', info.stdout))
    if not versions:
        raise SystemExit('无法确定构建产物的 glibc 依赖。')
    return max(versions, key=lambda value: tuple(map(int, value.split('.'))))


def stage(root, bundle):
    application = root / 'opt' / NAME
    application.parent.mkdir(parents=True)
    shutil.copytree(bundle, application, symlinks=True)
    binary = root / 'usr/bin/just_translator'
    binary.parent.mkdir(parents=True)
    binary.symlink_to('/opt/shiyi-translator/just_translator')
    desktop = root / 'usr/share/applications/dev.justtranslator.just_translator.desktop'
    desktop.parent.mkdir(parents=True)
    shutil.copyfile(PROJECT / 'packaging' / desktop.name, desktop)
    icon = root / 'usr/share/icons/hicolor/64x64/apps/dev.justtranslator.just_translator.png'
    icon.parent.mkdir(parents=True)
    shutil.copyfile(PROJECT / 'assets/tray.png', icon)
    return sum(file.stat().st_size for file in root.rglob('*') if file.is_file() and not file.is_symlink())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, default=PROJECT / 'build/linux/x64/release/bundle')
    parser.add_argument('--output', type=Path, default=PROJECT / 'dist')
    args = parser.parse_args()
    bundle, output = args.bundle.resolve(), args.output.resolve()
    for tool in ['dpkg-deb', 'bsdtar', 'zstd', 'readelf']:
        if not shutil.which(tool):
            raise SystemExit(f'缺少打包工具：{tool}')
    executable = bundle / 'just_translator'
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise SystemExit('请先执行 flutter build linux --release。')
    header = executable.read_bytes()[:20]
    if header[:5] != b'\x7fELF\x02' or header[5] != 1 or header[18:20] != b'\x3e\x00':
        raise SystemExit('仅支持 Linux x86_64 ELF 构建产物。')
    match = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$', (PROJECT / 'pubspec.yaml').read_text(), re.M)
    if not match:
        raise SystemExit('版本号需使用 x.y.z+构建号 格式。')
    version, revision = match.groups()
    glibc = glibc_requirement(bundle)
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='shiyi-packages-') as temporary:
        root = Path(temporary)
        deb, arch = root / 'deb', root / 'arch'
        size = stage(deb, bundle)
        stage(arch, bundle)
        control = deb / 'DEBIAN/control'
        control.parent.mkdir()
        control.write_text(f'''Package: {NAME}
Version: {version}-{revision}
Section: utils
Priority: optional
Architecture: amd64
Maintainer: {MAINTAINER}
Installed-Size: {(size + 1023) // 1024}
Depends: libc6 (>= {glibc}), libstdc++6, libgtk-3-0 | libgtk-3-0t64, libsecret-1-0, libayatana-appindicator3-1, espeak-ng
Recommends: wl-clipboard, xclip
Homepage: {URL}
Description: Shiyi desktop translator
 Translate selected text using configurable translation services.
''')
        deb_path = output / f'{NAME}_{version}-{revision}_amd64.deb'
        run('dpkg-deb', '--root-owner-group', '-Zxz', '--build', str(deb), str(deb_path))
        (arch / '.PKGINFO').write_text(f'''pkgname = {NAME}
pkgbase = {NAME}
pkgver = {version}-{revision}
pkgdesc = Desktop translator with configurable translation services
url = {URL}
builddate = {int(os.environ.get('SOURCE_DATE_EPOCH', time.time()))}
packager = {MAINTAINER}
size = {size}
arch = x86_64
xdata = pkgtype=pkg
depend = glibc>={glibc}
depend = gcc-libs
depend = gtk3
depend = libsecret
depend = libayatana-appindicator
depend = espeak-ng
optdepend = wl-clipboard: Wayland selection capture
optdepend = xclip: X11 selection capture
''')
        entries = ['.PKGINFO', 'opt', 'usr']
        mtree = run('bsdtar', '--format=mtree', '--options=!all,use-set,type,uid,gid,mode,time,size,sha256,link',
                    '--uid', '0', '--gid', '0', '-cf', '-', *entries, cwd=arch, capture_output=True).stdout
        (arch / '.MTREE').write_bytes(gzip.compress(mtree, mtime=0))
        arch_path = output / f'{NAME}-{version}-{revision}-x86_64.pkg.tar.zst'
        run('bsdtar', '--zstd', '--uid', '0', '--gid', '0', '--uname', 'root', '--gname', 'root',
            '-cf', str(arch_path), '.PKGINFO', '.MTREE', 'opt', 'usr', cwd=arch)
        print(f'已生成：{deb_path}\n已生成：{arch_path}\n最低 glibc：{glibc}')


if __name__ == '__main__':
    main()
