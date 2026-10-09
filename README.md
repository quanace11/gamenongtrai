# Ruộng Lúa Nước — game nông trại góc nhìn thứ nhất (Godot 4)

Prototype Godot 4 cho game nông trại lúa nước góc nhìn thứ nhất, giúp người thành phố và khách quốc tế trải nghiệm một vụ lúa ở làng quê Việt Nam: lội bùn, cuốc đất, cấy lúa theo nhịp, giữ nước, thả vịt, gặt, đập lúa và "chạy thóc" khi mưa rào ập tới.

- Thiết kế: [docs/GDD.md](docs/GDD.md), cuối file có bảng những gì prototype đã làm và chưa làm.
- Không có asset ngoài: hình khối low-poly và âm thanh (ếch nhái, bùn, liềm, sấm…) đều tạo bằng GDScript khi khởi động.

## Chạy thử

1. Cài [Godot 4.3](https://godotengine.org/download) (bản Standard, không cần .NET).
2. Mở Godot, chọn **Import** và trỏ tới `project.godot` trong thư mục này.
3. Bấm **Run** (F5).

Hoặc chạy bằng dòng lệnh: `godot --path .`

Khi chạy từ editor (bản debug), các phím `F6`–`F9` cho phép nhảy giai đoạn: `F6` làm đất và mạ xong, `F7` đã cấy, `F8` lúa chín, `F9` gặt xong và có thóc trong thùng.

### Tự kiểm tra

```sh
godot --path . -- --autotest                 # chơi tự động hết một vụ, in PASS/FAIL, thoát mã 1 nếu lỗi
godot --path . -- --autotest --shots=/tmp/s  # kèm ảnh chụp màn hình từng giai đoạn
```

## Điều khiển

| Phím | Việc |
|---|---|
| `W A S D`, `Shift` | Đi, chạy (tốn sức) |
| Chuột | Nhìn quanh |
| Chuột trái | Dùng dụng cụ đang cầm (giữ để bừa / lùa vịt) |
| Chuột phải | Cào vun thóc |
| `E` | Tương tác (giữ để lặp: nhổ mạ, đập lúa, vớt bèo…) |
| `1`–`7` | Tay không, Cuốc, Bừa, Gàu sòng, Liềm, Cào, Sào vịt |
| `Q` | Huýt sáo gọi đàn vịt |
| `Esc` | Tạm dừng |
| Mini-game cấy | `Space` lùi · `A` trái · `S` giữa · `D` phải · `Enter` nhờ hàng xóm cấy nốt |

## Một vụ lúa trong prototype

1. **Làm đất**: cuốc ruộng khô (đất khô tốn sức gấp đôi), mở cửa cống bờ tây dẫn nước từ mương, rồi cầm bừa giữ chuột trái đi khắp ruộng đến khi bùn nhuyễn.
2. **Ươm & cấy mạ**: ngâm thóc ở thúng cạnh sân, ngủ qua đêm cho thóc nứt nanh, gieo lên vạt mạ, tưới 3 ngày, nhổ đủ 8 bó, rồi vào ruộng bấm `E` để cấy theo nhịp. Cấy thẳng hàng thì được điểm *Thẩm mỹ đồng ruộng* (tối đa +15% sản lượng, ít sâu bệnh hơn). Cấy xong một làn có thể nhờ hàng xóm "đổi công" cấy nốt.
3. **Chăm sóc**: giữ nước 3–5 cm bằng cửa cống (nước mương chỉ dâng tới ~6 cm), rãnh xả bờ đông, hoặc gàu sòng khi mương cạn. Rắc tro bếp lúc sáng sớm còn sương, bóc trứng ốc bươu vàng trên cọc tre, thả vịt khi lúa non và lùa ra khi lúa trổ bông. Ngủ ở võng để lúa lớn (8 ngày).
4. **Thu hoạch & phơi**: gặt bằng liềm, gánh về thùng đập lúa, đổ thóc ra sân gạch rồi rải mỏng. Mưa rào được báo trước 90 giây: vun thóc vào khung bạt, kéo bạt, chặn đủ 4 viên gạch. Nếu không kịp, thóc ướt sẽ lên mầm và tụt loại gạo.

Nhánh phụ: vớt bèo tây, băm, nấu cháo heo với cám (bếp còn cho tro), cho lợn ăn, rồi lấy bùn vi sinh từ hầm biogas về bón ruộng. Vịt đẻ trứng mỗi sáng ở chuồng.

## Cấu trúc

```
project.godot, scenes/main.tscn
scripts/main.gd        vòng lặp game, thời gian, thời tiết, tương tác, các giai đoạn, autotest
scripts/field.gd       thửa ruộng: độ tơi, độ nhuyễn, mực nước, sâu hại, khóm lúa
scripts/transplant.gd  mini-game cấy lúa theo nhịp
scripts/courtyard.gd   sân phơi thóc, bạt, mưa
scripts/ducks.gd       đàn vịt chạy đồng
scripts/player.gd      góc nhìn thứ nhất, lội bùn, sức lực
scripts/tools.gd       dụng cụ cầm tay và động tác
scripts/world.gd       cảnh vật dựng bằng code
scripts/layout.gd      toạ độ mọi thứ trên bản đồ
scripts/hud.gd         giao diện
scripts/audio.gd       âm thanh tổng hợp
```
