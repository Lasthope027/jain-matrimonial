"""Resumable official-tool downloads; concurrent HTTP ranges with hash verification."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import hashlib
import re
import urllib.request


def download(url, path, checksum=None):
    path = Path(path)
    if path.exists():
        if checksum and hashlib.sha256(path.read_bytes()).hexdigest() != checksum:
            raise ValueError(f'Checksum mismatch: {path.name}')
        return path
    temporary = path.with_suffix('.download')
    request = urllib.request.Request(url, headers={'Range': 'bytes=0-0'})
    with urllib.request.urlopen(request, timeout=90) as response:
        content_range = response.headers.get('Content-Range', '')
        match = re.fullmatch(r'bytes 0-0/(\d+)', content_range)
    if not match:
        with urllib.request.urlopen(url, timeout=120) as response, temporary.open('wb') as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
    else:
        total = int(match[1])
        existing = temporary.stat().st_size if temporary.exists() else 0
        if existing > total:
            raise ValueError('Existing download is larger than the remote file')
        ranges = [(start, min(start + 8 * 1024 * 1024, total) - 1)
                  for start in range(existing, total, 8 * 1024 * 1024)]

        def part(bounds):
            start, end = bounds
            fragment = temporary.with_name(temporary.name + f'.{start}.part')
            size = end - start + 1
            if fragment.exists() and fragment.stat().st_size == size:
                return fragment
            request = urllib.request.Request(url, headers={'Range': f'bytes={start}-{end}'})
            with urllib.request.urlopen(request, timeout=120) as response:
                if response.headers.get('Content-Range') != f'bytes {start}-{end}/{total}':
                    raise ValueError('Server returned an unexpected download range')
                with fragment.open('wb') as output:
                    while chunk := response.read(1024 * 1024):
                        output.write(chunk)
            if fragment.stat().st_size != size:
                raise ValueError('Truncated download range')
            print(f'{path.name}: {end + 1}/{total}', flush=True)
            return fragment

        with ThreadPoolExecutor(max_workers=4) as executor:
            fragments = list(executor.map(part, ranges))
        with temporary.open('ab') as output:
            for fragment in fragments:
                with fragment.open('rb') as source:
                    while chunk := source.read(1024 * 1024):
                        output.write(chunk)
                fragment.unlink()
    if checksum and hashlib.sha256(temporary.read_bytes()).hexdigest() != checksum:
        raise ValueError(f'Checksum mismatch: {path.name}')
    temporary.replace(path)
    return path
