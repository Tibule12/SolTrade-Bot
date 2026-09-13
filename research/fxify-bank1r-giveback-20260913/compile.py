#!/usr/bin/env python3
import hashlib, json, os, shutil, subprocess
from pathlib import Path

HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[1]
PREFIX=Path('/home/tibule12/.wine-fpmarkets'); TERM=PREFIX/'drive_c/v202-validation-terminal'
results=[]
for target in ('fxify-10k','fxify-100k'):
    d=HERE/'release'/target; src=next(d.glob('*.mq5')); dest=TERM/'MQL5/Experts'/src.name
    shutil.copy2(src,dest); log=TERM/f'{src.stem}-compile.log'
    proc=subprocess.run(['wine',str(TERM/'MetaEditor64.exe'),f'/compile:C:\\v202-validation-terminal\\MQL5\\Experts\\{src.name}',f'/log:C:\\v202-validation-terminal\\{log.name}'],env=dict(os.environ,WINEPREFIX=str(PREFIX),WINEDEBUG='-all',DISPLAY=':1'),capture_output=True,timeout=120)
    txt=log.read_text(encoding='utf-16'); (d/'compile.log').write_text(txt)
    ok='0 errors, 0 warnings' in txt
    if not ok: raise SystemExit(txt[-3000:])
    shutil.copy2(dest.with_suffix('.ex5'),d/dest.with_suffix('.ex5').name)
    results.append({'target':target,'compile':'0 errors, 0 warnings','source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'binary_sha256':hashlib.sha256((d/dest.with_suffix('.ex5').name).read_bytes()).hexdigest()})
(HERE/'release'/'compile-results.json').write_text(json.dumps(results,indent=2)+'\n')
print(json.dumps(results,indent=2))
