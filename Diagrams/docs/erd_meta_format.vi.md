# Mô tả file `*.meta.json` (định dạng `erd-meta-v1`) cho công cụ sinh ERD

Mục đích: Agent chỉ viết file `xxx.meta.json` (nguồn chuẩn), công cụ `Diagrams\Gen-Erd.ps1` tự đặt vị trí bảng, nối đường và sinh `xxx.gen.drawio`.
Ví dụ thật: `F:\VScode\MKDC-IoT\Agent\tt02_api\Mau_02_Ban_QL_KKT\document\erd_mau_02.meta.json` (18 bảng, 32 quan hệ). Ví dụ nhỏ để thử: `F:\script\Diagrams\examples\erd\erd_demo.meta.json`.

Công cụ chỉ ĐỌC các khóa liệt kê dưới đây; mọi khóa khác trong file (`conventions`, `terms`, `enums`, `word_mapping`, `decisions`, `changelog`, `on_delete`, `mermaid`, `csharp_class`, `note`...) được BỎ QUA, nên cứ để nguyên cho mục đích khác.

## 1. Nhận dạng file

File được coi là ERD khi có CẢ BA: `schema_version` là CHUỖI `"1"` (không phải số 1), mảng `tables`, mảng `relationships`, và KHÔNG có khóa `kind`. Gọi `--kind erd` (hoặc dùng `Gen-Erd.ps1`) để ép: file loại khác sẽ báo lỗi.

## 2. Cấp gốc

| Khóa | Bắt buộc | Dùng để |
|------|----------|---------|
| `schema_version` | có | phải là `"1"` |
| `tables` | có | mảng bảng (mục 3) |
| `relationships` | có | mảng quan hệ (mục 4), có thể rỗng |
| `mau.ten_mau` | không | tiêu đề trên cùng của sơ đồ |
| `version` | không | ghép sau tiêu đề (` - <version>`) |

## 3. Một bảng trong `tables[]`

| Khóa | Bắt buộc | Ý nghĩa / cách vẽ |
|------|----------|-------------------|
| `name` | có | tên bảng, là id nên không có khoảng trắng, ký tự điều khiển hay dấu `:` (1..200 ký tự); không được trùng |
| `kind` | có | `NEW` (bảng mới, nền trắng, tiêu đề `[NEW]`), `EXTEND` (bảng có sẵn, thêm/đổi cột, xám nhạt, `[EXTEND]`), `REUSE` (dùng nguyên, xám đậm, `[REUSE]`) |
| `columns[]` | không | cột: `name` (bắt buộc, quy tắc như tên bảng), `pg_type` (kiểu, thiếu thì hiện `?`), `nullable` (chỉ `true` mới thêm ` NULL`), `change` (chuỗi như `ADD`, `ALTER_DROP_NOT_NULL`; chỉ hiện ở bảng EXTEND, dạng ` (ADD)`) |
| `primary_key[]` | không | danh sách cột khóa chính; thiếu thì là `["id"]`; không được rỗng |
| `foreign_keys[].columns[]` | không | cột nào là khóa ngoại (in nghiêng, role FK); `ref_table` bị bỏ qua |
| `uniques[]`, `indexes[]` | không | `{name, columns}` -> dòng ghi chú `UK name(cột, cột)` / `IX name(...)` |
| `checks[]` | không | `{name, expr}` -> dòng ghi chú `CK name: expr` |
| `other_columns` | không | có giá trị (khác rỗng) ở bảng EXTEND -> thêm dòng `... cac cot khac khong doi` |

Cột audit (`created_at`, `updated_by`, `is_deleted`...) KHÔNG khai trong `columns` thì không vẽ (theo quy ước của file).

### Bảng hiện những dòng nào

| kind | Các dòng (theo thứ tự) |
|------|------------------------|
| NEW | cột khóa chính, rồi MỌI cột trong `columns`, rồi cột FK suy từ quan hệ mà chưa có dòng |
| EXTEND | cột khóa chính, rồi cột trong `columns` mà là FK HOẶC có `change` (theo thứ tự khai), rồi FK suy từ quan hệ, rồi dòng `other_columns` |
| REUSE | cột khóa chính + cột FK suy từ quan hệ (không cần khai `columns`) |

Cuối cùng là các dòng ghi chú UK, IX, CK. Mỗi cột đúng MỘT dòng (cột vừa là khóa chính vừa FK: một dòng, đậm, hậu tố ` PK FK`). Nhãn dòng: `tên kiểu` + ` NULL` + ` (change)` + ` PK`. Nhãn ghi chú dài hơn 56 ký tự bị cắt kèm `...`; nhãn dài quá bề rộng bảng cũng bị cắt.

## 4. Một quan hệ trong `relationships[]`

| Khóa | Bắt buộc | Ý nghĩa |
|------|----------|---------|
| `parent` | có | bảng "một" (phải có trong `tables`) |
| `child` | có | bảng giữ khóa ngoại (phải có trong `tables`) |
| `fk_column` | có | tên cột FK trong bảng `child` |
| `parent_card` | có | số lượng ở phía parent: `"1"`, `"0..1"`, `"0..N"`, `"1..N"` |
| `child_card` | có | số lượng ở phía child: cùng tập giá trị |
| `label` | không | chữ ghi trên đường (nhiều dòng không hỗ trợ, một nhãn) |

Ký hiệu đầu đường: `"1"` = một bắt buộc, `"0..1"` = không hoặc một, `"0..N"` = không hoặc nhiều (chân quạ tròn), `"1..N"` = một hoặc nhiều. Id cạnh trong XML là `rel.<child>.<fk_column>` (trùng thì thêm `_2`, `_3`).

- Hai FK cùng một cặp bảng (ví dụ `bao_cao_id` và `bao_cao_nguon_id`) là HAI quan hệ riêng, mỗi cái một đường và một cổng riêng.
- Chu trình (A -> B và B -> A): đường có trọng số thấp hơn bị vẽ ngược lên trên. Trọng số: `parent_card = "1"` -> 8; còn lại `child_card = "0..1"` -> 1; còn lại -> 4. Muốn bảng nào nằm TRÊN thì để quan hệ của nó là "bắt buộc" (parent_card `"1"`).
- Quan hệ tự trỏ (`parent == child`): vẽ vòng bên phải bảng; tối đa 3 vòng một bảng và bảng phải đủ cao.
- Khóa ngoại khai trong `foreign_keys` mà không có quan hệ tương ứng: vẫn đánh dấu FK nhưng không có đường, và in `warning:`.

## 5. Giới hạn và lỗi thường gặp (mã thoát 1, thông báo ASCII có đường dẫn trường)

| Lỗi | Nguyên nhân |
|-----|-------------|
| `schema_version` | không phải chuỗi `"1"` |
| `tables[i].name ... duplicate` | trùng tên bảng |
| `tables[i].kind` | không phải NEW/EXTEND/REUSE |
| `relationships[i].parent` / `child` | tên bảng không có trong `tables` |
| `relationships[i].parent_card` | ngoài `1`, `0..1`, `0..N`, `1..N` |
| `fk_column` / `primary_key[j]` | rỗng, có khoảng trắng hoặc `:` |
| `bang X: qua nhieu quan he tren mot mat` | hơn 38 đường vào một mặt (trên hoặc dưới) của một bảng |
| `khong dinh tuyen duoc ma khong chong doan` | hiếm: không tìm được cách nối không chồng đoạn |

Độ rộng bảng tự tính từ chữ (200..440 px) và tự rộng thêm (tối đa 800 px) khi nhiều đường dồn vào một mặt.

## 6. Mẹo viết meta.json để sơ đồ đẹp

1. Luôn khai ĐỦ `relationships` (kể cả `fk_column`); đó là thứ quyết định đường nối và cột FK của bảng REUSE.
2. Bảng REUSE không cần `columns`; bảng EXTEND chỉ cần các cột đổi/thêm có `change`.
3. `parent_card = "1"` cho FK bắt buộc (NOT NULL); đường bắt buộc được ưu tiên đặt cha ở trên con.
4. Tránh quan hệ nối cùng cặp bảng quá nhiều lần; mỗi cái tốn một cổng.
5. Ghi chú dài đặt trong `note` của bảng (bị bỏ qua) thay vì `label` của quan hệ.

## 7. Chạy

    cd F:\script
    .\Diagrams\Gen-Erd.ps1 "đường\dẫn\xxx.meta.json"      # ra xxx.gen.drawio cạnh file meta
    python -B -m diagram_tool xxx.meta.json -o D:\ra       # tương đương, từ F:\script\Diagrams

Kết quả không đè bản vẽ tay `xxx.drawio` (đuôi `.gen.drawio` khác). Chi tiết thuật toán: `F:\script\Diagrams\docs\erd.md`. Chưa mở bằng draw.io thật: hình dạng ký hiệu chân quạ và độ rộng chữ là phần chưa kiểm.

Báo cáo được khởi tạo bởi Claude Code (Model: Sonnet 5.5 — Anthropic) 🚀
