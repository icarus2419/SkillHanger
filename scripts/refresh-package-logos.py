#!/usr/bin/env python3
"""Bundle original PNG logos declared by Codex plugin manifests. Never execute package code."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import hashlib
import json
import struct
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'Sources/AgentAwakeApp/Assets'

def fetch(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'SkillHanger-logo-builder'}), timeout=30) as response:
        data = response.read(1_000_001)
    if len(data) > 1_000_000:
        raise ValueError('Logo or manifest exceeds the size limit')
    return data

def collect(item):
    if item['kind'] != 'plugin' or item['agents'] != ['codex']:
        return None
    prefix = item['path'] + '/' if item['path'] else ''
    base = 'https://raw.githubusercontent.com/' + item['repository'] + '/' + item['revision'] + '/'
    try:
        interface = json.loads(fetch(base + prefix + '.codex-plugin/plugin.json')).get('interface', {})
        logo = interface.get('logo', '').removeprefix('./')
        if not logo.lower().endswith('.png'):
            return None
        if logo.startswith('/') or ':' in logo or '\\' in logo or any(p in ('', '.', '..') for p in logo.split('/')):
            raise ValueError('Unsafe logo path')
        data = fetch(base + prefix + logo)
        if not data.startswith(b'\x89PNG\r\n\x1a\n') or len(data) < 24:
            raise ValueError('Expected a PNG logo')
        width, height = struct.unpack('>II', data[16:24])
        if not 0 < width <= 4096 or not 0 < height <= 4096:
            raise ValueError('Logo dimensions exceed limits')
        name = 'catalog-' + hashlib.sha256(item['id'].encode()).hexdigest()[:20]
        destination = ASSETS / 'PackageLogos' / (name + '.png')
        destination.parent.mkdir(exist_ok=True)
        destination.write_bytes(data)
        item['logoName'] = name
        return dict(itemID=item['id'], repository=item['repository'], revision=item['revision'], path=prefix+logo,
                    asset=name+'.png', bytes=len(data), pixels=[width, height])
    except Exception as error:
        return dict(itemID=item['id'], error=str(error))

if __name__ == '__main__':
    path = ASSETS / 'marketplace-catalog.json'
    catalog = json.loads(path.read_text())
    with ThreadPoolExecutor(max_workers=8) as pool:
        evidence = [result for result in pool.map(collect, catalog) if result]
    path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + '\n')
    report = ROOT / 'tasks/evidence/marketplace-expansion/package-logo-provenance.json'
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(evidence, indent=2) + '\n')
    print('Bundled', sum('asset' in result for result in evidence), 'logos;', sum('error' in result for result in evidence), 'errors')
