Dưới đây là {{NMODELS}} danh sách lỗi review PR #{{N}} "{{TITLE}}" của: {{MODEL_IDS}}.
Không cần đọc code. Chỉ gộp danh sách:

- Các lỗi cùng cơ chế (cùng root cause hoặc cùng kiểu vi phạm rule), dù ở chỗ khác nhau → gộp thành 1, gộp đủ danh sách "Chỗ tương tự" và "Đường vào" của các model (bỏ trùng), ghi ai tìm, vd "Tìm bởi: Claude + Codex (C2, X1)"; mọi model cùng tìm thì ghi "Tìm bởi: Tất cả (…)".
- Lỗi chỉ một model có → giữ nguyên, ghi "Tìm bởi: <tên model> (<ID>)".
- Các model khác mức độ → ghi đủ, vd "Mức: major (Claude) / minor (Codex)".
- Đánh số lại I1, I2…, xếp blocker → major → minor. Không thêm, không bỏ lỗi nào.

Format mỗi lỗi (giữ nội dung gốc, viết gọn):

### I1 [mức] <tiêu đề ngắn> — `file:line`
- Tìm bởi: …
- Issue: …
- Chỗ tương tự: `file:line`, … (hoặc "Không có")
- Đường vào: … (chỉ khi có)
- Root cause: …
- Solution: …

Mọi danh sách đều "Không có lỗi" thì chỉ in "Không có lỗi".
