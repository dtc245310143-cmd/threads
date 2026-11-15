from pathlib import Path
import hashlib
import json
import urllib.request

ROOT=Path(__file__).resolve().parents[1]
folder=ROOT/'ThreadsStudio/Library/voice'
folder.mkdir(exist_ok=True)
assets=[
 ('vieneu.gguf','https://huggingface.co/pnnbao-ump/VieNeu-TTS-v3-Turbo/resolve/61b85e3d937fbbacb387714180e8182823512523/gguf/vieneu-v3-turbo-q8_0.gguf','a60569e5d7dd6f24cbb7bb2e7c472bb988ad19563a4e78f0cc67cc53fd189bb4',187917664),
 ('sea_g2p.bin','https://github.com/pnnbao97/sea-g2p/releases/download/v0.10.0/sea_g2p.bin','4346e690d0711ebc5231e7a42c5c88aaf6e40377e894b4617c018fd81c6f4096',62829820),
]
for name,url,digest,size in assets:
    path=folder/name
    if path.exists() and path.stat().st_size==size and hashlib.file_digest(path.open('rb'),'sha256').hexdigest()==digest:continue
    temporary=path.with_suffix('.download')
    try:
        total=0;sha=hashlib.sha256()
        with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'ThreadsStudio-iOS'}),timeout=90) as response,temporary.open('wb') as output:
            while chunk:=response.read(1024*1024):
                total+=len(chunk)
                if total>size:raise ValueError('Unexpected voice model size')
                sha.update(chunk);output.write(chunk)
        if total!=size or sha.hexdigest()!=digest:raise ValueError('Voice model checksum mismatch: '+name)
        temporary.replace(path)
    finally:temporary.unlink(missing_ok=True)
for name in ['speaker.emb.txt','ref_codes.txt','reference-info.json']:
    if not (folder/name).is_file():raise ValueError('Missing desktop reference: '+name)
manifest={'model_revision':'61b85e3d937fbbacb387714180e8182823512523','model_format':'Q8_0 / f16 codec','assets':[{'file':n,'source':u,'sha256':h,'bytes':s} for n,u,h,s in assets]}
(folder/'model-manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('Verified desktop voice assets:',sum((folder/name).stat().st_size for name,_,_,_ in assets),'bytes')
