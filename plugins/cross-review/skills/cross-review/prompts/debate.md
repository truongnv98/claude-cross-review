Em là {{ID}}. Ở các lỗi dưới đây, các model ({{MODELS}}) recheck ra kết luận khác nhau.
Dòng "{{ID}}:" là ý kiến của em, các dòng còn lại là của model khác.

Với TỪNG lỗi: đọc lập luận của các model khác, kiểm lại đúng các dòng code các bên dẫn, rồi chốt.
- Chỉ đổi ý khi bằng chứng của bên khác đúng trong code. Không nhượng bộ cho êm.
- Giữ ý thì phải chỉ ra chỗ lập luận bên khác sai (dòng code, input cụ thể).
Chỉ đọc, không sửa file, không gọi mạng. Đây là vòng duy nhất, không có vòng sau.

Mỗi lỗi in đúng 1 khối:

### I<số> — GIỮ | ĐỔI → ĐÚNG | SAI | MỘT PHẦN
- Phản biện: bên khác đúng/sai ở đâu
- Bằng chứng: `file:line`, đường đi của code, input/trạng thái cụ thể
- Mức đúng: blocker | major | minor
- Root cause / Solution: "giữ nguyên", hoặc bản sửa lại

Không thêm lỗi mới. Dưới 600 từ.
