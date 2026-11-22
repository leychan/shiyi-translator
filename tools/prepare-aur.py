#!/usr/bin/env python3
"""从已发布的 Arch 安装包生成 AUR 的 PKGBUILD。"""

import argparse
from collections import defaultdict
import hashlib
from pathlib import Path
import re
from shlex import quote
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('tag')
    parser.add_argument('source_url')
    args = parser.parse_args()
    archive = args.archive

    # 从安装包读取依赖，确保 AUR 与直装包使用相同的运行条件。
    info = subprocess.check_output(['tar', '--zstd', '-xOf', str(archive), '.PKGINFO'], text=True)
    metadata = defaultdict(list)
    for line in info.splitlines():
        key, separator, value = line.partition(' = ')
        if separator:
            metadata[key].append(value)

    match = re.fullmatch(r'shiyi-translator-(\d+\.\d+\.\d+)-([1-9]\d*)-x86_64\.pkg\.tar\.zst', archive.name)
    if not match:
        raise SystemExit(f'无法从 Arch 安装包文件名读取版本：{archive.name}')
    version, revision = match.groups()
    if (args.tag != f'v{version}' or metadata['pkgver'] != [f'{version}-{revision}']
            or metadata['pkgname'] != ['shiyi-translator'] or metadata['arch'] != ['x86_64']):
        raise SystemExit('Git 标签、文件名与 Arch 安装包内的版本或架构不匹配。')

    with archive.open('rb') as package:
        checksum = hashlib.file_digest(package, 'sha256').hexdigest()
    depends = ' '.join(map(quote, metadata['depend']))
    optional_depends = ' '.join(map(quote, metadata['optdepend']))
    (archive.parent / 'PKGBUILD').write_text(f'''# Maintainer: leychan <leychan_@outlook.com>
pkgname=shiyi-translator-bin
pkgver={version}
pkgrel={revision}
pkgdesc={quote(metadata['pkgdesc'][0])}
arch=('x86_64')
url={quote(metadata['url'][0])}
license=('unknown')
depends=({depends})
optdepends=({optional_depends})
provides=("shiyi-translator=$pkgver")
conflicts=('shiyi-translator')
options=('!strip' '!debug')
_archive={quote(archive.name)}
source=({quote(args.source_url)})
noextract=("$_archive")
sha256sums=('{checksum}')

package() {{
    # Let makepkg set ownership and generate fresh metadata for the -bin package.
    bsdtar --no-same-owner -xf "$srcdir/$_archive" -C "$pkgdir" opt usr
}}
''', encoding='utf-8')


if __name__ == '__main__':
    main()
