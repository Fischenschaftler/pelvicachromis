"""Create disposable photo-loader fixtures; requires Pillow. Never edits source photo."""
from pathlib import Path
from PIL import Image, ImageOps
import hashlib,json
ROOT=Path(__file__).resolve().parent.parent
folder=ROOT/'.godot/photo_import_fixtures';folder.mkdir(parents=True,exist_ok=True)
photo=Image.open(ROOT/'blender/reference/pelvicachromis_taeniatus_male.jpg').convert('RGB')
for name,size in [('Großes Fischfoto.jpg',(4000,3000)),('Hochformat.png',(600,1000)),('Klein.jpeg',(80,60)),('Test.webp',(900,500))]:
    ImageOps.pad(photo,size,color=(16,22,26)).save(folder/name)
(folder/'Defekt.png').write_bytes(b'not a valid PNG file')
(ROOT/'godot/diagnostics/photo_source_hashes.json').write_text(json.dumps({str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in folder.iterdir()},indent=2))
