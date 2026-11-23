Đây là danh sách lỗi đã gộp từ {{NMODELS}} reviewer (em và các model khác) cho PR em vừa review.
Kiểm lại TỪNG lỗi trong code (kể cả lỗi của chính em), không tin sẵn lỗi nào.
Chỉ đọc, không sửa file, không gọi mạng.

Mỗi lỗi in đúng 1 khối:

### I<số> — ĐÚNG | SAI | MỘT PHẦN
- Bằng chứng: `file:line`, đường đi của code, input/trạng thái cụ thể
- Mức đúng: blocker | major | minor (nếu khác mức đang ghi thì nói lý do)
- Chỗ tương tự: grep lại cùng kiểu lỗi. "đủ", hoặc ghi chỗ thiếu (`file:line`) / chỗ ghi sai
- Đường vào: "đủ", hoặc đường thiếu / đường ghi sai
- Root cause / Solution: "giữ nguyên", hoặc bản sửa lại nếu sai/thiếu

Lỗi đúng, chỉ thiếu chỗ tương tự / đường vào → vẫn ghi ĐÚNG, ghi phần bổ sung ở 2 dòng trên.
Không thêm lỗi khác kiểu (chỉ bổ sung chỗ tương tự / đường vào cho lỗi đã có).
Danh sách ghi "Không có lỗi" thì chỉ in "Không có mục". Viết gọn, khoảng 80 từ/lỗi.
