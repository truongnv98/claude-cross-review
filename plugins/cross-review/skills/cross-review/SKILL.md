---
name: cross-review
description: Review PR bằng 3 model — Claude, Codex, Gemini (agy) — review độc lập, gộp có ghi ai tìm, cùng recheck toàn bộ, tranh luận khi khác kết luận, rồi tổng hợp issue / root cause / solution. Dùng khi user gõ /cross-review, hoặc nói "review chéo", "cross review", "3 con review", "Claude + Codex review PR".
argument-hint: <số PR hoặc URL> [ghi chú trọng tâm]
---

# cross-review

`review.sh` chạy B1–B4 bằng CLI headless, luôn với 3 model: Claude (`claude -p`),
Codex (`codex exec`), Gemini (`agy`, mặc định `gemini-4-neon-medium`):

0. Kiểm tra đăng nhập (không tốn token): model nào chưa đăng nhập thì bỏ.
   PR đã merge thì diff lấy theo merge commit; PR không có thay đổi → script báo lỗi.
1. Các model review độc lập, song song (ID lỗi: Claude C*, Codex X*, Gemini G*).
2. Gộp các danh sách thành 1 (I1..In), ghi rõ ai tìm.
3. Các model recheck toàn bộ danh sách gộp: ĐÚNG / SAI / MỘT PHẦN + bằng chứng.
   Mỗi model resume phiên review của chính nó (đã đọc code, có cache) nên rẻ.
   3.5. Bước rẻ ghi `disputes.md`: **bảng kết luận** (mỗi lỗi × model: kết luận + mức + bản sửa lại)
   và các lỗi khác **kết luận**. Chỉ khác mức thì không tranh luận.
4. Có bất đồng → tranh luận ĐÚNG 1 vòng: mỗi model đọc lập luận các bên khác, chốt GIỮ/ĐỔI.
5. Em (phiên này) tổng hợp kết quả cuối.

**Model hỏng.** Ở B1/B3, model lỗi (hết hạn đăng nhập, hết hạn mức/token, quá giờ, trả rỗng,
lệnh bị chặn) bị bỏ, ghi lý do; còn dưới 2 model thì script dừng. Ở B4, model lỗi giữ kết luận
recheck. Bước gộp/lọc (rẻ, không tool) dùng Claude Sonnet; Claude hỏng thì Codex effort low.

**Quyền.** Claude: chỉ tool đọc. Codex: `--sandbox read-only`. agy: `--sandbox --mode auto` +
`AGY_SETTINGS` cho sẵn lệnh đọc (account chưa có `auto` thì agy tự về mode mặc định, vẫn chạy) + `prompts/gemini-tools.md`; rỗng hoặc lệnh bị chặn → tự chạy lại
1 lần. KHÔNG dùng `--dangerously-skip-permissions`.

Prompt ở `prompts/` (tên model điền qua `{{MODELS}}`). Model, effort, timeout, thư mục cấu hình Claude
riêng, email Claude bắt buộc: mặc định ở đầu `review.sh`, ghi đè trong
`~/.config/cross-review/config.env` (mẫu: `config.example.env` ở gốc repo plugin).
User muốn model khác cho lần chạy này → thêm biến trước lệnh, vd `GEMINI_MODEL=<tên>` (`agy models` để xem tên).

`review.sh` nằm cùng thư mục với file SKILL.md này ("Base directory for this skill" khi skill được nạp).
Bên dưới gọi thư mục đó là `<SKILL_DIR>`. Chạy lệnh từ thư mục git của repo cần review.

## Việc của em

**Bước 0 — Cài đặt lần đầu (chỉ khi chưa có file cấu hình).** Kiểm tra
`${CROSS_REVIEW_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/cross-review/config.env}`. Đã có → bỏ qua bước này.
Chưa có → chạy `bash "<SKILL_DIR>/review.sh" --setup` (không tốn token), đọc báo cáo rồi:

1. Dòng `THIẾU` công cụ (`gh`, `jq`, `timeout`…) hoặc `gh chưa đăng nhập` → báo user lệnh cài/đăng nhập
   (macOS: `brew install gh jq coreutils`, `gh auth login`), dừng, chưa ghi config.
2. `claude` / `codex` / `agy` chưa cài hoặc chưa đăng nhập → báo user lệnh đăng nhập (`codex login`, đăng
   nhập agy, `claude` → `/login`). Còn ít nhất 2 model dùng được thì vẫn tiếp tục được; dưới 2 thì dừng.
3. `agy không có <model>` → chọn model gemini tốt nhất trong danh sách báo cáo in ra, ưu tiên cùng dòng,
   mức `medium` (vd `gemini-4-neon-medium`), ghi `GEMINI_MODEL`.
4. Dòng `claude:` cho biết email đang dùng. Hỏi user đúng 1 câu: review bằng tài khoản Claude này, hay
   một thư mục cấu hình Claude khác (vd tài khoản công ty)? Khác → ghi `CLAUDE_HOME` (+ `CLAUDE_EXPECT_EMAIL`
   nếu user muốn khoá email), rồi chạy lại `--setup` để kiểm tài khoản đó đã đăng nhập.
5. Ghi file cấu hình (tạo thư mục nếu chưa có), chỉ gồm các dòng khác mặc định + 1 dòng comment ngày tạo.
   Không có gì khác mặc định thì vẫn ghi file chỉ có comment, để lần sau không chạy lại bước này.
   Báo user 1–2 dòng: đã ghi gì, ở đâu, sửa lại thế nào. Rồi tiếp tục Bước A0.

Model Codex / Claude mặc định không kiểm được miễn phí: nếu lần review đầu báo model đó lỗi kiểu "model
không tồn tại / không có quyền", sửa `CODEX_MODEL` / `CLAUDE_MODEL` trong file cấu hình theo model user có.

**Bước A0 — Jira (chỉ khi mô tả PR nhắc tới ticket và phiên này có Atlassian MCP).** Script tự lấy
mô tả, commit, comment của PR; riêng Jira phải do em đọc (phiên headless không có MCP):

```bash
gh pr view <PR> --json body -q .body | grep -oE 'atlassian\.net/browse/[A-Z][A-Z0-9]+-[0-9]+|\b[A-Z][A-Z0-9]{1,9}-[0-9]+\b' | sort -u
```

- Không ra gì, hoặc phiên không có Atlassian MCP → bỏ qua A0, không truyền tham số thứ 3.
- Có mã → đọc bằng Atlassian MCP (`getJiraIssue`), ghi ngắn gọn (summary, mô tả yêu cầu,
  acceptance criteria; bỏ log/ảnh/meta) vào `${TMPDIR:-/tmp}/cross-review-<N>-jira.md`.
  Nhiều ticket thì ghi chung 1 file, mỗi ticket 1 mục. Mã trần không tìm thấy (vd `UTF-8`) → bỏ qua
  mã đó; link Jira đọc lỗi → báo user, không chạy tiếp.

**Bước A** — chạy nền (Bash `run_in_background: true`, timeout 3600000), trả lời user
1 dòng "Đang review PR #N", rồi **kết thúc lượt**. Không đọc diff, không review:

```bash
bash "<SKILL_DIR>/review.sh" <PR> "<ghi chú trọng tâm, có thể bỏ trống>" [file jira từ A0]
```

**Bước B** — khi lệnh xong (harness tự đánh thức):

- Lỗi: báo user dòng `LỖI ở bước: …` (bước, model nào hỏng + lý do, thư mục log). Không tự chạy lại.
- Thành công: đọc đúng các file dòng cuối output liệt kê: `merged.md`, `disputes.md` (bảng kết luận
  + bất đồng), và khi có tranh luận thì `<model>-debate.md`. Chỉ mở `<model>-check.md` khi bảng
  thiếu/khó hiểu ở một lỗi cụ thể. Phần "Model: … · Bỏ/lỗi: …" ở dòng cuối cho biết model nào
  đã tham gia. Không đọc code, trừ khi sau tranh luận các model vẫn bất đồng (khi đó chỉ đọc đúng
  dòng code các bên dẫn).

Quyết từng lỗi:
- Recheck cùng kết luận → theo đó (cùng ĐÚNG → giữ, cùng SAI → loại, cùng MỘT PHẦN → giữ bản sửa lại).
  Chỉ khác mức → em chọn mức (theo đa số + lý do các bên), ghi mức từng model.
- Recheck khác kết luận → xem kết quả tranh luận (kết luận sau GIỮ/ĐỔI của mỗi bên):
  - Sau tranh luận cùng kết luận → theo đó.
  - Vẫn bất đồng → em quyết dựa trên lập luận cuối của các bên + đúng dòng code tranh cãi.
    Ghi "Em quyết (lý do)".
- Không tự quyết lỗi nào đang khác kết luận mà chưa qua tranh luận.

Trả lời user bằng tiếng Việt, gọn:

Câu đầu: merge được / cần sửa trước khi merge, đếm theo mức. Model nào bị bỏ thì nói 1 dòng (lý do).
Rồi blocker → major → minor, mỗi lỗi:

```
### [mức] <tiêu đề ngắn> — `path:line`
- **Issue:** …
- **Root cause:** … (lời thường: chuyện gì xảy ra, vì sao)
- **Sửa ở:** app (store) | giao diện | API — chỗ gây ra lỗi
- **Solution:** … (snippet ngắn nếu cần)
- **Tìm bởi:** Claude | Codex | Gemini | … · **Recheck:** Claude ĐÚNG, Codex SAI, Gemini ĐÚNG · **Tranh luận:** Codex đổi → ĐÚNG (chỉ khi có) · (Em quyết: lý do)
```

Cuối: "Đã loại" — lỗi + lý do. Không đăng gì lên GitHub.
