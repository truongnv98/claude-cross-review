Dưới đây là danh sách lỗi đã gộp (I1..In) của PR #{{N}} "{{TITLE}}" và kết quả recheck của {{NMODELS}} model: {{MODELS}}.
Không cần đọc code. In 2 phần, không thêm lỗi, không tự phán ai đúng.

## Bảng kết luận
Mỗi lỗi 1 dòng, đủ mọi lỗi I1..In, theo đúng recheck:
`I<số> · <Model> <ĐÚNG|SAI|MỘT PHẦN> <mức> · <Model> … · Sửa lại: <bản sửa root cause/solution ngắn, chỉ khi có model ghi MỘT PHẦN hoặc sửa lại; không thì bỏ> · Bổ sung chỗ: <chỗ tương tự / đường vào các model ghi thêm, gộp bỏ trùng; không có thì bỏ>`

## Bất đồng
Chỉ các lỗi có ít nhất 2 model khác KẾT LUẬN (ĐÚNG / SAI / MỘT PHẦN). Cùng kết luận mà khác mức
hoặc khác lý do → không đưa vào đây. Mỗi lỗi 1 khối, chép đủ lập luận và bằng chứng gốc của
từng model (viết gọn, giữ `file:line`):

### I<số> [mức] <tiêu đề ngắn> — `file:line`
- Lỗi gốc: Issue / Root cause / Solution từ danh sách gộp
- <Model>: <ĐÚNG|SAI|MỘT PHẦN> — <bằng chứng, mức đúng, sửa đổi đề xuất>
  (mỗi model 1 dòng: {{MODELS}})

Không có lỗi nào khác kết luận thì phần này chỉ có đúng một dòng: KHÔNG CÓ BẤT ĐỒNG
Danh sách gộp ghi "Không có lỗi" thì chỉ in: Không có lỗi. KHÔNG CÓ BẤT ĐỒNG
