# Ruộng Lúa Nước — game nông trại góc nhìn thứ nhất

Prototype trình duyệt (Three.js) cho game nông trại lúa nước góc nhìn thứ nhất, giúp người thành phố và khách quốc tế trải nghiệm một vụ lúa ở làng quê Việt Nam: lội bùn, cuốc đất, cấy lúa theo nhịp, giữ nước, thả vịt, gặt, đập lúa và "chạy thóc" khi mưa rào ập tới.

- Thiết kế: [docs/GDD.md](docs/GDD.md) (kèm bảng những gì prototype đã làm / chưa làm)
- Không cần build, không có asset ngoài: hình khối low-poly và âm thanh tổng hợp bằng WebAudio.

## Chạy thử

Cần một web server tĩnh (ES modules không chạy được qua `file://`):

```sh
python3 -m http.server 8000
# hoặc: npx http-server -p 8000
```

Mở <http://localhost:8000>. Nên chơi trên máy tính, có chuột và bật loa.

- `?low` — tắt bóng đổ, cho máy yếu.
- `?debug` — bật phím tắt nhảy giai đoạn: `F6` làm đất + mạ xong, `F7` đã cấy, `F8` lúa chín, `F9` gặt xong, có thóc trong thùng; đối tượng `window.game` để kiểm tra.

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
| Mini-game cấy | `Space` lùi · `A` trái · `S` giữa · `D` phải |

## Một vụ lúa trong prototype

1. **Làm đất** — cuốc ruộng khô (đất khô tốn sức gấp đôi), mở cửa cống bờ tây dẫn nước từ mương, cầm bừa giữ chuột trái đi khắp ruộng đến khi bùn nhuyễn.
2. **Ươm & cấy mạ** — ngâm thóc ở thúng cạnh sân, ngủ qua đêm cho nứt nanh, gieo lên vạt mạ, tưới 3 ngày, nhổ đủ 8 bó, vào ruộng bấm `E` để cấy theo nhịp. Hàng thẳng → điểm *Thẩm mỹ đồng ruộng* (tối đa +15% sản lượng, ít sâu bệnh). Xong một làn có thể nhờ hàng xóm "đổi công" cấy nốt.
3. **Chăm sóc** — giữ nước 3–5 cm (cửa cống, rãnh xả bờ đông, gàu sòng khi mương cạn), rắc tro bếp lúc sáng sớm còn sương, bóc trứng ốc bươu vàng trên cọc tre, thả vịt khi lúa non và lùa ra khi lúa trổ bông. Ngủ ở võng để lúa lớn (8 ngày).
4. **Thu hoạch & phơi** — gặt bằng liềm, gánh về thùng đập lúa, đổ thóc ra sân gạch, rải mỏng. Mưa rào báo trước 90 giây: vun thóc vào khung bạt, kéo bạt, chặn đủ 4 viên gạch, nếu không thóc ướt sẽ lên mầm và tụt loại gạo.

Nhánh phụ: vớt bèo tây → băm → nấu cháo heo với cám (bếp còn cho tro) → cho lợn ăn → hầm biogas cho bùn vi sinh để bón ruộng; vịt đẻ trứng mỗi sáng ở chuồng.

## Cấu trúc

```
index.html, style.css   HUD và màn hình
src/main.js             vòng lặp game, thời gian, thời tiết, tương tác, các giai đoạn
src/field.js            thửa ruộng: độ tơi, độ nhuyễn, mực nước, sâu hại, khóm lúa
src/transplant.js       mini-game cấy lúa theo nhịp
src/courtyard.js        sân phơi thóc, bạt, mưa
src/ducks.js            đàn vịt chạy đồng
src/player.js, tools.js góc nhìn thứ nhất, lội bùn, dụng cụ cầm tay
src/world.js, layout.js cảnh vật và toạ độ
src/audio.js            âm thanh tổng hợp (ếch nhái, bùn, liềm, sấm…)
vendor/                 three.js r160 (MIT)
```
