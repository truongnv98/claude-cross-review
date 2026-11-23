# cross-review

[English](README.md) | Tiếng Việt

Plugin Claude Code review một GitHub PR bằng **3 model**: Claude, Codex và Gemini (qua `agy`).

1. Mỗi model review độc lập, song song.
2. Gộp các danh sách lỗi thành một, ghi rõ model nào tìm ra.
3. Mỗi model kiểm lại toàn bộ danh sách gộp (ĐÚNG / SAI / MỘT PHẦN + bằng chứng `file:line`).
4. Lỗi nào các model khác kết luận thì tranh luận đúng 1 vòng.
5. Phiên Claude Code của bạn tổng hợp kết quả cuối: lỗi theo mức, nguyên nhân, nên sửa ở app / giao diện / API.

Model nào chưa đăng nhập, hết hạn mức hoặc lỗi thì tự bị bỏ (có ghi lý do). Còn dưới 2 model thì dừng.
Mọi model chỉ đọc code: Claude chỉ có tool đọc, Codex chạy `--sandbox read-only`, agy chạy
`--sandbox` với danh sách lệnh đọc cho phép sẵn.

> Kết quả review trả lời theo ngôn ngữ bạn dùng với Claude Code; prompt nội bộ gửi các model viết bằng tiếng Việt.

## Cài đặt

Trong Claude Code:

```
/plugin marketplace add truongnv98/claude-cross-review
/plugin install cross-review@cross-review
```

Cập nhật bản mới: `/plugin marketplace update cross-review`.

### Công cụ cần có

| Công cụ | Dùng để | Cài (macOS) |
|---|---|---|
| `gh` (đã `gh auth login`) | lấy PR, diff, comment | `brew install gh` |
| `git`, `jq`, `perl` | xử lý dữ liệu | `brew install jq` |
| `timeout` | giới hạn thời gian mỗi bước | `brew install coreutils` |
| `claude` (đã đăng nhập) | reviewer Claude | có sẵn khi dùng Claude Code |
| `codex` (đã `codex login`) | reviewer Codex | xem tài liệu Codex CLI |
| `agy` (đã đăng nhập) | reviewer Gemini | xem tài liệu Antigravity CLI |

Thiếu `claude` / `codex` / `agy` thì model đó bị bỏ; cần ít nhất 2 trong 3.

### Cấu hình

Lần đầu chạy `/cross-review`, Claude tự kiểm máy (`review.sh --setup`, không tốn token): công cụ còn thiếu,
3 CLI đã đăng nhập chưa, model Gemini nào có. Rồi nó hỏi bạn đúng 1 câu (dùng tài khoản Claude nào) và tự
ghi `~/.config/cross-review/config.env`. Muốn tự sửa sau đó: xem mẫu `config.example.env`.

Đổi được: model và effort từng bên, timeout, thư mục cấu hình Claude riêng (vd tài khoản công ty),
email Claude bắt buộc. File này nằm trên máy bạn, không nằm trong repo.

Effort mặc định để `medium` (Claude, Codex) và `gemini-4-neon-medium` cố ý, để tiết kiệm quota: mức `high`
tốn quota gấp nhiều lần. PR lớn cần soi kỹ thì nâng riêng lần đó, vd
`CLAUDE_EFFORT=high CODEX_EFFORT=high GEMINI_MODEL=gemini-4-neon-high`, hoặc ghi vào `config.env`.

## Dùng

Mở Claude Code trong thư mục repo cần review, rồi:

```
/cross-review 123
/cross-review https://github.com/org/repo/pull/123 tập trung vào xử lý lỗi mạng
```

Review chạy nền khoảng 10–40 phút tuỳ độ lớn PR. Kết quả trung gian nằm ở `$TMPDIR/cross-review-<số PR>/`.
Plugin không đăng gì lên GitHub.

Nếu mô tả PR có mã Jira và phiên Claude Code có Atlassian MCP, ticket được đọc thêm làm ngữ cảnh.

## Lưu ý

- Code của PR được gửi tới cả 3 nhà cung cấp (Anthropic, OpenAI, Google). Kiểm tra quy định bảo mật
  của công ty bạn, và tắt chia sẻ dữ liệu để train trên tài khoản nếu cần.
- Mọi lệnh gọi dùng CLI chính thức bằng tài khoản của chính bạn; không gọi API ẩn, không kiểm tra quota trước.

## License

MIT
