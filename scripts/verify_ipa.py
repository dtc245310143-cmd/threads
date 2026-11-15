from pathlib import Path
import plistlib
import struct
import sys
import zipfile

path=Path(sys.argv[1])
with zipfile.ZipFile(path) as archive:
    assert archive.testzip() is None,'Corrupt IPA archive'
    root='Payload/ThreadsStudio.app/'
    plist=plistlib.loads(archive.read(root+'Info.plist'))
    assert plist['CFBundlePackageType']=='APPL'
    assert 'iPhoneOS' in plist.get('CFBundleSupportedPlatforms',[]),'Simulator build is not installable on iPhone'
    executable=archive.read(root+plist['CFBundleExecutable'])
    assert executable[:4]==b'\xcf\xfa\xed\xfe','Expected arm64 Mach-O, not an EXE or source archive'
    cpu=struct.unpack_from('<I',executable,4)[0]
    assert cpu==0x0100000c,'Expected arm64 device binary'
    assert root+'ThreadsScan.js' in archive.namelist()
    assert any(name.startswith(root+'Library/music/') and name.endswith('.mp3') for name in archive.namelist())
print('Verified device IPA:',path,path.stat().st_size)
