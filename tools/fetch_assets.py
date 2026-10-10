#!/usr/bin/env python3
"""Re-download the CC0 Poly Haven assets used by the game into assets/.

Usage: python3 tools/fetch_assets.py [target_dir]

Existing files are skipped. Model textures are then shrunk to 512 px with
ImageMagick (`mogrify -resize '512x512>' -quality 85 assets/models/*/textures/*.jpg`).
Open the project in Godot afterwards so it imports the files.
"""
import json,urllib.request,os,sys
UA={'User-Agent':'gamenongtrai-asset-fetch/1.0'}
def get(u): return json.load(urllib.request.urlopen(urllib.request.Request(u,headers=UA),timeout=60))
def dl(u,p):
  os.makedirs(os.path.dirname(p),exist_ok=True)
  if os.path.exists(p): return
  data=urllib.request.urlopen(urllib.request.Request(u,headers=UA),timeout=120).read()
  open(p,'wb').write(data)
root=sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', 'assets')
tex=['brown_mud_03','farm_soil','mud_cracked_dry_03','leafy_grass','grass_path_2','red_brick_pavers','clay_roof_tiles_02','yellow_plaster','bamboo_wall','weathered_planks','thatch_roof_angled','dirt']
for t in tex:
  f=get('https://api.polyhaven.com/files/'+t)
  for k,suf in [('Diffuse','diff'),('nor_gl','nor'),('arm','arm')]:
    dl(f[k]['1k']['jpg']['url'], f'{root}/textures/{t}/{t}_{suf}_1k.jpg')
  print('tex',t,flush=True)
for h,res in [('kloofendal_48d_partly_cloudy_puresky','2k'),('qwantani_sunset_puresky','1k'),('qwantani_night_puresky','1k'),('kloofendal_overcast_puresky','1k')]:
  f=get('https://api.polyhaven.com/files/'+h)
  dl(f['hdri'][res]['hdr']['url'], f'{root}/hdri/{h}_{res}.hdr'); print('hdri',h,flush=True)
mods=['wicker_basket_02','wicker_basket_01','wooden_bucket_02','wooden_bucket_01','ceramic_pot','planter_pot_clay','stone_fire_pit','watering_can_metal_01','wooden_crate_01','rock_07','stone_01','tree_stump_01','fern_02','shrub_04','nettle_plant','weed_plant_02','hatchet']
for m in mods:
  f=get('https://api.polyhaven.com/files/'+m)
  g=f['gltf']['1k']['gltf']
  dl(g['url'], f'{root}/models/{m}/{m}_1k.gltf')
  for rel,v in g['include'].items(): dl(v['url'], f'{root}/models/{m}/{rel}')
  print('model',m,flush=True)

# ---- VEG package: cut-out leaves for the Poly Haven plants --------------
# Their glTFs say alphaMode MASK but ship a 3-channel JPEG diffuse, so the
# leaf cards render as opaque quads. Merge the separate alpha map into an
# RGBA PNG diffuse (fern_02, seen close up in pots, at 1024 px; the rest at
# 512 px) and point the glTF image at it. Needs Pillow. Re-download the 1k
# diffuse here: the model loop's copy is shrunk to 512 px by mogrify.
LEAF_PX={'fern_02':1024}
def cut_out_leaves(m):
  from PIL import Image
  d=f'{root}/models/{m}/textures'
  png=f'{d}/{m}_diff_1k.png'
  jpg=f'{d}/{m}_diff_1k.jpg'
  if os.path.exists(png):
    # the model loop above re-fetches the glTF's original JPEG; drop it
    if os.path.exists(jpg): os.remove(jpg)
    return
  f=get('https://api.polyhaven.com/files/'+m)
  dl(f['Alpha']['1k']['png']['url'], f'{d}/{m}_alpha_1k.png')
  if os.path.exists(jpg): os.remove(jpg)
  dl(f['Diffuse']['1k']['jpg']['url'], jpg)
  px=LEAF_PX.get(m,512)
  a=Image.open(f'{d}/{m}_alpha_1k.png')
  if a.mode in ('I','I;16','I;16B'): a=a.point(lambda v: v/257).convert('L')
  a=a.convert('L').resize((px,px),Image.LANCZOS)
  rgb=Image.open(jpg).convert('RGB').resize((px,px),Image.LANCZOS)
  rgb.putalpha(a); rgb.save(png)
  g=f'{root}/models/{m}/{m}_1k.gltf'
  s=open(g).read().replace(f'{m}_diff_1k.jpg',f'{m}_diff_1k.png')
  import re
  s=re.sub(r'"image/jpeg",(\s*"name": "[^"]*",)?(\s*"uri": "textures/'+m+r'_diff_1k\.png")', r'"image/png",\1\2', s)
  open(g,'w').write(s)
  os.remove(f'{d}/{m}_alpha_1k.png'); os.remove(jpg)
  print('leaves',m,flush=True)
for m in ['fern_02','shrub_04','nettle_plant','weed_plant_02']:
  cut_out_leaves(m)

# ---- package WORLD: terrain, house, karst textures (CC0) and the pig (CC-BY 4.0)
for t in ['sparse_grass','grass_path_3','worn_mossy_plasterwall','rock_pitted_mossy']:
  f=get('https://api.polyhaven.com/files/'+t)
  for k,suf in [('Diffuse','diff'),('nor_gl','nor'),('arm','arm')]:
    dl(f[k]['1k']['jpg']['url'], f'{root}/textures/{t}/{t}_{suf}_1k.jpg')
  print('tex',t,flush=True)
# "Realistic Pig / Porco 3D Model" by William Aleixo, CC-BY 4.0 (see assets/CREDITS.md),
# from a public GitHub mirror of the Sketchfab download.
pig='https://raw.githubusercontent.com/2blackhole/fuzzy-goggles/HEAD/normik/models/realistic_pig/'
for rel,dst in [('scene.gltf','pig_1k.gltf'),('scene.bin','scene.bin'),('textures/Material_baseColor.png','textures/Material_baseColor.png'),('textures/Material.001_baseColor.png','textures/Material.001_baseColor.png')]:
  dl(pig+rel, f'{root}/models/pig/{dst}')
print('model pig',flush=True)

# ---- PLAYER package: first-person hands and sleeve cloth --------------------
# Hands: CC0 1.0, Godot XR Tools hand models by DigitalN8m4r3 (Miodrag Sejic).
# hand_r/l.gltf are Hand_Nails_R/L.gltf renamed. The farmer skin texture is a
# 50/50 mix of the caucasian and african realistic base colours, warmed
# (x 1.0, 0.95, 0.86) and desaturated to 82 %. poses.json holds the last key
# of each rotation track of animations/{right,left}/{Grip,Grip Shaft,Hold,
# Pinch Tight,Cup}.res, exported with Godot (Animation.track_get_key_value).
XR='https://raw.githubusercontent.com/GodotVR/godot-xr-tools/master/addons/godot-xr-tools/hands/'
hands=os.path.join(root,'models','hands')
dl(XR+'License.md', f'{hands}/License.md')
for side in 'RL':
  dl(XR+f'model/Hand_Nails_{side}.gltf', f'{hands}/hand_{side.lower()}.gltf')
for t in ['caucasian_realistic_baseColor.png','african_realistic_baseColor.png','hands_normal.png','hands_occlusionRoughnessMetallic.png']:
  dl(XR+'textures/'+t, f'{hands}/source/{t}')
try:
  from PIL import Image
  import numpy as np
  c=np.asarray(Image.open(f'{hands}/source/caucasian_realistic_baseColor.png').convert('RGB')).astype(float)
  a=np.asarray(Image.open(f'{hands}/source/african_realistic_baseColor.png').convert('RGB')).astype(float)
  m=(c*0.5+a*0.5)*np.array([1.0,0.95,0.86]); g=m.mean(axis=2,keepdims=True); m=g+(m-g)*0.82
  os.makedirs(f'{hands}/textures',exist_ok=True)
  Image.fromarray(np.clip(m,0,255).astype(np.uint8)).save(f'{hands}/textures/hands_farmer_baseColor.jpg',quality=90)
  Image.open(f'{hands}/source/hands_normal.png').convert('RGB').save(f'{hands}/textures/hands_normal.png',optimize=True)
  Image.open(f'{hands}/source/hands_occlusionRoughnessMetallic.png').convert('RGB').save(f'{hands}/textures/hands_orm.jpg',quality=90)
except ImportError:
  print('install pillow + numpy to rebuild the hand textures')
print('hands',flush=True)
f=get('https://api.polyhaven.com/files/rough_linen')
for k,suf in [('Diffuse','diff'),('nor_gl','nor'),('arm','arm')]:
  dl(f[k]['1k']['jpg']['url'], f'{root}/textures/rough_linen/rough_linen_{suf}_1k.jpg')
print('tex rough_linen',flush=True)
# ---- end PLAYER package ------------------------------------------------------
