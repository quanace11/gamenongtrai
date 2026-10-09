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
