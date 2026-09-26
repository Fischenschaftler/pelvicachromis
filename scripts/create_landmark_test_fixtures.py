"""Create disposable landmark test inputs; never modify original photos or fish assets."""
from pathlib import Path
import json
import math
from PIL import Image
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / '.godot/landmark_fixtures'
OUT.mkdir(parents=True, exist_ok=True)
photo = Image.open(ROOT / '.godot/photo_import_fixtures/Großes Fischfoto.jpg').convert('RGBA')
mask = Image.open(ROOT / 'godot/diagnostics/mask_fish_4000x3000.png').convert('L')
points = [(500 + x * 3.75, y * 3.75) for x, y in [(730,297),(669,275),(236,371),(246,429),(554,244),(410,435)]]
cases = []
for name, reduced, flip, angle in [('large_right',False,False,0),('left',True,True,0),('up',True,False,12),('down',True,False,-24),('small',True,False,0)]:
    size = (160,120) if name == 'small' else ((800,600) if reduced else (4000,3000))
    image = photo.resize(size)
    alpha = mask.resize(size, Image.Resampling.NEAREST)
    coords = [(x * size[0] / 4000, y * size[1] / 3000) for x,y in points]
    if flip:
        image = image.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        alpha = alpha.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        coords = [(size[0] - x, y) for x,y in coords]
    if angle:
        image = image.rotate(angle, resample=Image.Resampling.BICUBIC)
        alpha = alpha.rotate(angle, resample=Image.Resampling.NEAREST)
        a = math.radians(angle)
        c, s = math.cos(a), math.sin(a)
        cx, cy = size[0]/2, size[1]/2
        coords = [(cx+c*(x-cx)+s*(y-cy), cy-s*(x-cx)+c*(y-cy)) for x,y in coords]
    image.save(OUT / f'{name}.png')
    alpha.save(OUT / f'{name}_mask.png')
    cases.append(dict(name=name, photo=str(OUT / f'{name}.png'), mask=str(OUT / f'{name}_mask.png'), points=coords))
(OUT/'cases.json').write_text(json.dumps(cases), encoding='utf8')
