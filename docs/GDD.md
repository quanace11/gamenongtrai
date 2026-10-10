# Game Design Document — Game nông trại lúa nước góc nhìn thứ nhất (FPV)

> Mục tiêu: người thành phố và khách quốc tế trực tiếp trải nghiệm đời sống nhà nông Việt Nam qua góc nhìn thứ nhất (First-Person Perspective). Lợi thế của FPV là cảm giác xúc giác (tactile feedback) và sự đắm chìm (immersion): bước chân xuống bùn lún, nghe tiếng ếch nhái râm ran, tay cầm liềm gặt lúa, hay chạy vắt chân lên cổ cào thóc khi giông kéo đến.

Tài liệu này mô tả **Lõi Gameplay (Core Loop)**. Phạm vi đã có trong bản prototype xem ở mục cuối.

---

## 1. Chu trình Lúa nước 4 giai đoạn (Wet-Rice Simulation)

Cơ chế môi trường cốt lõi dựa trên 3 thông số của thửa ruộng:

- **Độ mịn của đất** (Mud Texture)
- **Mực nước** (Water Level)
- **Chỉ số dinh dưỡng / sâu hại** (Nutrient & Pest Index)

### Giai đoạn 1 – Làm đất & Cày ải (Soil Preparation)

**Tác vụ thủ công (giai đoạn đầu)**

- Dùng cuốc xới từng góc đất khô nứt nẻ.
- Cảm giác FPV: chuyển động cuốc đập xuống nặng tay, stamina tụt nhanh nếu đất quá khô cứng.
- Mở cửa đập / be bờ bằng xẻng để dẫn nước từ mương vào. Người chơi cầm bừa gỗ kéo bằng tay để đánh bùn nhuyễn nhũn đến khi mặt ruộng phẳng lì và nổi lớp bùn mịn (puddle).

**Nâng cấp – Trâu cày**

- Dắt trâu xuống ruộng, móc ách bừa.
- Cơ chế: điều khiển trâu bằng dây thừng và khẩu lệnh ("Tắc", "Rì", "Họ"). Trâu đi theo đường zíc-zắc đánh tơi đất nhanh gấp 4 lần, nhưng tiêu tốn cỏ/rơm cho trâu ăn và cần tắm cho trâu tránh sốc nhiệt.

**Cơ giới hóa**

- Máy cày mini (máy xới tay / máy xới bèo): đi lội bùn rung tay cầm (haptic rumble), tiêu tốn dầu diesel, làm xong thửa ruộng chỉ trong vài phút thực tế.

### Giai đoạn 2 – Ươm & Cấy mạ (Seed Nursery & Transplanting)

**Ươm mạ**

- Ngâm thóc giống trong thúng nước ấm, ủ rơm đến khi nảy mầm (nứt nanh).
- Gieo đều tay trên vạt đất riêng sát nhà. Tưới nước xăm xắp trong 3–5 ngày in-game để mạ lên xanh non.

**Nhổ mạ & Bó mạ**

- Cúi người nhổ từng túm mạ, gõ nhẹ gốc vào mu bàn chân để rũ sạch bùn rễ, dùng lạt tre buộc thành từng bó mạ rồi gánh ra ruộng lớn.

**Mini-game Cấy lúa**

- Cơ chế FPV: tay trái cầm bó mạ, tay phải tách 3–4 tép mạ cắm xuống bùn.
- Nhịp điệu (rhythm-based): vạch căn hàng hiển thị mờ dưới bùn. Bấm phím nhịp nhàng theo bước lùi: Lùi 1 bước → Cắm bên trái → Cắm ở giữa → Cắm bên phải.
- Đánh giá: hàng cấy thẳng, khoảng cách đều đặn tạo điểm **"Thẩm mỹ đồng ruộng"** (tăng 15% sản lượng và giảm nguy cơ nấm bệnh do thông thoáng gió).

### Giai đoạn 3 – Chăm sóc & Bảo vệ (Water & Pest Management)

**Điều tiết nước**

- Ruộng lúa nước không thể ngập quá sâu (ngập bẹ mạ sẽ thối) cũng không được cạn (nứt nẻ khiến cỏ dại mọc lấn át).
- Người chơi giữ mực nước ở mức 3–5 cm bằng cách đắp/khoét rãnh bờ ruộng, hoặc tát nước bằng gàu sòng/gàu dây vào những ngày nắng gắt.

**Trị rầy nâu & Ốc bươu vàng**

- Cách thủ công sinh học: rắc tro bếp khô vào sáng sớm khi sương còn đọng trên lá để diệt sâu cuốn lá; cắm cọc tre bẫy ốc bươu vàng đẻ trứng đỏ để bóc bỏ.
- Cách thiên địch: mở bờ xả đàn vịt non vào ruộng (xem mục Chăn nuôi).

### Giai đoạn 4 – Thu hoạch & Sấy phơi (Harvest & Sun Drying)

**Gặt lúa**

- Cầm liềm tay trái gom khóm lúa, tay phải lia lưỡi liềm sát gốc rạ (âm thanh "xoẹt xoẹt" giòn tai). Xếp lúa thành từng lượm rồi dùng đòn gánh gánh về sân.

**Tuốt lúa**

- Đầu game: đập lượm lúa vào thùng gỗ/thùng phi gắn nan tre để hạt thóc văng ra.
- Nâng cấp: bàn đạp tuốt lúa chân (máy tuốt quay bằng bàn đạp chân) → máy tuốt chạy dầu phát tiếng nổ tành tạch đặc trưng.

**Cơ chế "Chạy thóc"**

- Đổ thóc ra sân gạch đỏ, cầm cào gỗ rải mỏng thóc thành từng luống hình gợn sóng để đón nắng giòn.
- Sự kiện thời tiết ngẫu nhiên (mưa rào mùa hạ): trời bỗng sầm tối, gió nổi mạnh, sấm chớp báo hiệu mưa ập tới trong vòng 90 giây. Người chơi phải hối hả cào thóc vun đống, kéo bạt ni-lông phủ kín, lấy gạch chặn bốn góc. Nếu chậm trễ, thóc bị ướt mưa sẽ lên mầm, giảm chất lượng hạt gạo từ loại 1 xuống gạo nát/gạo chăn nuôi.

---

## 2. Mô hình Chăn nuôi sinh thái tuần hoàn (VAC / Lúa – Vịt – Cá)

Hệ thống được thiết kế theo vòng lặp tài nguyên khép kín, nơi phế phẩm của nhánh này là nguồn sống của nhánh kia.

```
       [Ruộng Lúa] ──(Gốc rạ, sâu bọ, ốc)──> [Đàn Vịt / Cá, Tôm]
            ▲                                      │
            │ (Bùn vi sinh, phân hữu cơ)           │ (Thịt, Trứng, Thủy sản)
            │                                      ▼
     (Chất thải)─── [Chuồng Lợn] ◄──(Bèo tây + Cám gạo)
```

### Mô hình Vịt chạy đồng

**Điều khiển**

- Người chơi cầm "Cây sào vịt" (cần tre buộc dải nilon bay phấp phới) và dùng phím còi/huýt sáo để định hướng đàn vịt (tương tự cơ chế lùa bầy trong các game mô phỏng sinh thái).

**Vòng đời sinh thái**

- Lúa non: thả vịt con/vịt nhỡ vào ruộng. Vịt lội sục bùn làm thoáng khí rễ lúa, ăn sạch ốc bươu vàng non và cỏ dại mà không làm dập nát lúa. Tiết kiệm 100% chi phí thức ăn trong 2 tuần.
- Lúa trổ bông: cấm thả vịt vào ruộng kẻo vịt rỉa bông lúa; lùa đàn ra kênh/sông hoặc đầm sen gần làng.
- Hậu thu hoạch: sau khi gặt, lùa vịt ra mót những hạt thóc rơi vãi sót lại trên gốc rạ để béo múp míp.

**Thu hoạch**

- Mỗi sáng xách rổ ra chuồng/bờ kênh nhặt trứng vịt trắng tinh.
- Vịt đủ cân bán cho thương lái tại chợ phiên hoặc giữ vịt mái già làm vịt đẻ giống.

### Mô hình Lợn – Khí sinh học (Biogas & Bèo tây)

**Chuỗi chế biến thức ăn**

- Lấy thuyền nan chèo ra ao/sông vớt bèo tây (lục bình).
- Đem về đặt lên thớt gỗ, cầm dao chuối băm nhỏ bèo tây (hoặc dùng cối xay quay tay).
- Trộn bèo với cám gạo (phế phẩm thu được từ cối xay thóc) và một ít nước, nấu sôi trên bếp củi tạo thành nồi cháo heo thơm nức khói lam chiều.

> *(Phần GDD gốc dừng ở đây; các mục tiếp theo của mô hình lợn – biogas cần được bổ sung.)*

---

## 3. Phạm vi bản prototype (vertical slice)

Bản prototype làm bằng **Godot 4.6 (GDScript)**, dùng texture, bầu trời HDRI và mô hình CC0 của Poly Haven cho bề mặt và đồ vật (cây cối làng quê, con vật và âm thanh vẫn tạo bằng code), và tập trung vào một vụ lúa hoàn chỉnh trên **một thửa ruộng 16 m × 16 m**. Thời gian trong game chạy 4 phút game / 1 giây thực; ngủ ở võng để qua đêm.

| Hạng mục GDD | Trạng thái trong prototype |
|---|---|
| 3 thông số ruộng: độ mịn đất, mực nước, dinh dưỡng/sâu hại | ✅ Mô phỏng và hiển thị trên HUD |
| Cuốc đất khô nứt, stamina tụt nhanh khi đất cứng | ✅ Đất khô tốn gấp đôi sức; cho nước vào trước thì đất mềm hơn |
| Mở cửa cống bằng xẻng dẫn nước từ mương, khoét rãnh xả | ✅ Cửa cống + rãnh xả bờ đông |
| Bừa tay đánh bùn nhuyễn | ✅ Giữ chuột trái và đi trong ruộng có nước |
| Trâu cày, máy xới | ⏳ Có con trâu đứng chờ, chưa điều khiển được |
| Ngâm thóc → nứt nanh → gieo → tưới 3 ngày → nhổ & bó mạ | ✅ |
| Mini-game cấy lúa theo nhịp (Lùi → Trái → Giữa → Phải), điểm Thẩm mỹ đồng ruộng | ✅ +15% sản lượng, giảm sâu bệnh; có "đổi công" nhờ hàng xóm cấy nốt |
| Giữ nước 3–5 cm, ngập thối, cạn mọc cỏ, gàu sòng ngày kênh cạn | ✅ |
| Rắc tro bếp buổi sáng sớm, bóc trứng ốc bươu vàng trên cọc tre | ✅ |
| Gặt bằng liềm, gánh lượm về sân, đập lúa vào thùng | ✅ |
| Máy tuốt đạp chân / chạy dầu | ⏳ Chưa làm |
| Chạy thóc: rải thóc, mưa rào 90 giây, vun đống, kéo bạt, chặn gạch 4 góc, thóc ướt hạ loại gạo | ✅ |
| Vịt chạy đồng: sào vịt, huýt sáo, vịt dọn ốc/cỏ lúc lúa non, cấm vịt khi trổ bông, nhặt trứng | ✅ (bản đơn giản) |
| Lợn – bèo tây – cám – cháo heo – biogas – bùn vi sinh bón ruộng | ✅ Bản rút gọn (vớt bèo ở bờ ao, chưa có thuyền nan) |
| Cá/tôm, chợ phiên, thương lái | ⏳ Chưa làm |
