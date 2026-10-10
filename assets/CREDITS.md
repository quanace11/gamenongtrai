# Nguồn asset

Toàn bộ texture, bầu trời HDRI và mô hình 3D trong thư mục này lấy từ [Poly Haven](https://polyhaven.com), phát hành theo giấy phép **CC0 1.0** (public domain): dùng tự do, kể cả thương mại, không bắt buộc ghi công. Danh sách dưới đây để tiện tra nguồn.

Texture ở độ phân giải 1k (albedo, normal OpenGL, ARM). Texture của mô hình được thu về 512 px để repo nhẹ hơn.

## Texture

| Asset | Dùng cho |
|---|---|
| [brown_mud_03](https://polyhaven.com/a/brown_mud_03) | bùn ruộng đã bừa, đáy mương, vạt mạ |
| [farm_soil](https://polyhaven.com/a/farm_soil) | đất đã cuốc; vân hạt thóc |
| [mud_cracked_dry_03](https://polyhaven.com/a/mud_cracked_dry_03) | ruộng khô nứt nẻ |
| [leafy_grass](https://polyhaven.com/a/leafy_grass) | bãi cỏ quanh nhà |
| [grass_path_2](https://polyhaven.com/a/grass_path_2) | bờ ruộng, lối mòn |
| [red_brick_pavers](https://polyhaven.com/a/red_brick_pavers) | sân gạch đỏ, gạch chặn bạt, bậc nhà |
| [clay_roof_tiles_02](https://polyhaven.com/a/clay_roof_tiles_02) | mái ngói |
| [yellow_plaster](https://polyhaven.com/a/yellow_plaster) | tường vôi vàng, chuồng lợn, hầm biogas |
| [bamboo_wall](https://polyhaven.com/a/bamboo_wall) | phên tre sau thùng đập lúa |
| [weathered_planks](https://polyhaven.com/a/weathered_planks) | cột nhà, cửa, cán cuốc, cửa cống |
| [thatch_roof_angled](https://polyhaven.com/a/thatch_roof_angled) | mái rạ chuồng lợn, chuồng vịt |
| [dirt](https://polyhaven.com/a/dirt) | bờ mương, máng lợn |

## Bầu trời (HDRI)

| Asset | Dùng cho |
|---|---|
| [kloofendal_48d_partly_cloudy_puresky](https://polyhaven.com/a/kloofendal_48d_partly_cloudy_puresky) | trời ban ngày |
| [qwantani_sunset_puresky](https://polyhaven.com/a/qwantani_sunset_puresky) | bình minh / hoàng hôn |
| [qwantani_night_puresky](https://polyhaven.com/a/qwantani_night_puresky) | ban đêm |
| [kloofendal_overcast_puresky](https://polyhaven.com/a/kloofendal_overcast_puresky) | trời giông |

## Mô hình 3D (glTF)

| Asset | Dùng cho |
|---|---|
| [wicker_basket_02](https://polyhaven.com/a/wicker_basket_02) | thúng ngâm thóc |
| [wicker_basket_01](https://polyhaven.com/a/wicker_basket_01) | rổ vớt bèo |
| [wooden_bucket_02](https://polyhaven.com/a/wooden_bucket_02) | thùng đập lúa |
| [wooden_bucket_01](https://polyhaven.com/a/wooden_bucket_01) | gàu cạnh mương |
| [ceramic_pot](https://polyhaven.com/a/ceramic_pot) | nồi cháo heo |
| [planter_pot_clay](https://polyhaven.com/a/planter_pot_clay) | chậu cây ở hiên |
| [stone_fire_pit](https://polyhaven.com/a/stone_fire_pit) | bếp củi |
| [watering_can_metal_01](https://polyhaven.com/a/watering_can_metal_01) | bình tưới mạ |
| [wooden_crate_01](https://polyhaven.com/a/wooden_crate_01) | hòm gỗ ở sân |
| [rock_07](https://polyhaven.com/a/rock_07) | đá ven ao, mương |
| [stone_01](https://polyhaven.com/a/stone_01) | sỏi đá |
| [tree_stump_01](https://polyhaven.com/a/tree_stump_01) | gốc cây làm thớt băm bèo |
| [fern_02](https://polyhaven.com/a/fern_02) | dương xỉ |
| [shrub_04](https://polyhaven.com/a/shrub_04) | bụi cây |
| [nettle_plant](https://polyhaven.com/a/nettle_plant) | cỏ dại |
| [weed_plant_02](https://polyhaven.com/a/weed_plant_02) | cỏ dại |
| [hatchet](https://polyhaven.com/a/hatchet) | dao băm bèo |

## Tự làm bằng code

Tre, chuối, cau, dừa, cỏ, khóm lúa, trâu, lợn, vịt, núi đá vôi, nước và mặt ruộng xa được dựng bằng GDScript và shader trong `scripts/flora.gd`, `scripts/world.gd` và `shaders/`, vì thư viện CC0 chưa có các mẫu mang dáng làng quê Việt Nam. Âm thanh vẫn được tổng hợp bằng code (`scripts/audio.gd`).

<!-- VEG package -->
## Lá cắt alpha cho cây Poly Haven (gói VEG)

`fern_02`, `shrub_04`, `nettle_plant`, `weed_plant_02` (CC0, Poly Haven): bản đồ Alpha 1k của chính các mẫu này được ghép vào ảnh màu thành `textures/<id>_diff_1k.png` (RGBA, 512 px) để lá được cắt đúng hình thay vì hiện thành tấm vuông. Cách làm nằm trong `tools/fetch_assets.py` (phần VEG). Cỏ sân, khóm lúa mọi giai đoạn, gốc rạ và vạt mạ được dựng bằng code trong `scripts/grass_lawn.gd`, `scripts/rice_hill.gd`, `scripts/rice_field.gd`, `scripts/flora.gd` và các shader `grass_lawn`, `grass_blade`, `rice*`.
<!-- /VEG package -->

## Gói WORLD (địa hình, nhà, núi đá, con vật)

Texture CC0 từ [Poly Haven](https://polyhaven.com) (tải lại bằng `tools/fetch_assets.py`):

| Asset | Dùng cho |
|---|---|
| [sparse_grass](https://polyhaven.com/a/sparse_grass) | bãi cỏ quanh nhà (`shaders/ground.gdshader`) |
| [grass_path_3](https://polyhaven.com/a/grass_path_3) | lối mòn đất nện, mặt bờ ruộng, bụi đất trên sân |
| [worn_mossy_plasterwall](https://polyhaven.com/a/worn_mossy_plasterwall) | vết ố, mốc trên tường vôi (`shaders/wall.gdshader`) |
| [rock_pitted_mossy](https://polyhaven.com/a/rock_pitted_mossy) | vân đá vôi trên núi (`shaders/karst.gdshader`), chân tảng cột |

Mô hình CC-BY 4.0 (phải ghi công tác giả):

| Asset | Tác giả | Giấy phép | Dùng cho |
|---|---|---|---|
| ["Realistic Pig / Porco 3D Model"](https://sketchfab.com/3d-models/realistic-pig-porco-3d-model-72834b8b47c7438c827cd0f2258ae656) | [William Aleixo (WildMesh3DFree)](https://sketchfab.com/WildMesh3DFree) | [CC BY 4.0](http://creativecommons.org/licenses/by/4.0/) | con lợn trong chuồng (`assets/models/pig/`) |

This work is based on "Realistic Pig / Porco 3D Model" (https://sketchfab.com/3d-models/realistic-pig-porco-3d-model-72834b8b47c7438c827cd0f2258ae656) by William Aleixo (https://sketchfab.com/WildMesh3DFree) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/). The file was taken unchanged from a public GitHub mirror of the Sketchfab download; in the game its roughness is raised so the skin is matte.

Trâu, vịt, bèo tây, núi đá vôi, tường, mái và sân gạch được dựng bằng code trong `scripts/world.gd`, `scripts/ducks.gd`, `scripts/courtyard.gd` và `shaders/` (ground, wall, roof, court, karst).

## Tay người chơi và áo (gói PLAYER)

| Asset | Tác giả · giấy phép | Dùng cho |
|---|---|---|
| [Godot XR Tools hand models](https://github.com/GodotVR/godot-xr-tools/tree/master/addons/godot-xr-tools/hands) (`Hand_Nails_R/L.gltf`, textures, grip poses) | DigitalN8m4r3 (Miodrag Sejic), dựng từ MakeHuman · [CC0 1.0](https://raw.githubusercontent.com/GodotVR/godot-xr-tools/master/addons/godot-xr-tools/hands/License.md) (bản sao ở `assets/models/hands/License.md`) | đôi tay cầm dụng cụ; màu da pha giữa hai texture realistic cho nước da nông dân rám nắng |
| [rough_linen](https://polyhaven.com/a/rough_linen) | colormass, Rico Cilliers · CC0 | ống tay áo nâu xắn lên |

Liềm, cuốc, đòn gánh, quang, lượm lúa và bó mạ được dựng bằng code trong `scripts/tools.gd`.
