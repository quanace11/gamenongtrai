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
# Skies (package LIGHT): hazy day, misty morning, soft sunset, night, storm.
for h,res in [('farm_field_puresky','2k'),('kloofendal_28d_misty_puresky','2k'),('rosendal_park_sunset_puresky','1k'),('qwantani_night_puresky','1k'),('kloofendal_overcast_puresky','1k')]:
  f=get('https://api.polyhaven.com/files/'+h)
  dl(f['hdri'][res]['hdr']['url'], f'{root}/hdri/{h}_{res}.hdr'); print('hdri',h,flush=True)
mods=['wicker_basket_02','wicker_basket_01','wooden_bucket_02','wooden_bucket_01','ceramic_pot','planter_pot_clay','stone_fire_pit','watering_can_metal_01','wooden_crate_01','rock_07','stone_01','tree_stump_01','fern_02','shrub_04','nettle_plant','weed_plant_02','hatchet']
for m in mods:
  f=get('https://api.polyhaven.com/files/'+m)
  g=f['gltf']['1k']['gltf']
  dl(g['url'], f'{root}/models/{m}/{m}_1k.gltf')
  for rel,v in g['include'].items(): dl(v['url'], f'{root}/models/{m}/{rel}')
  print('model',m,flush=True)
