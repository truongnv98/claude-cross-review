#!/usr/bin/env bash
# Review PR bằng 3 model: Claude công ty, Codex, Gemini (agy). Script chỉ điều phối CLI headless.
#   B0  Lấy diff, file ở PR head, ngữ cảnh PR; kiểm đăng nhập 3 model (không tốn token)
#   B1  Các model review độc lập, song song                → claude.md, codex.md, gemini.md
#   B2  1 lần gọi rẻ, không tool: gộp + ghi ai tìm         → merged.md (I1..In)
#   B3  Mỗi model RESUME phiên B1 của chính nó (có cache) recheck toàn bộ merged.md → <model>-check.md
#   B3.5 1 lần gọi rẻ: bảng kết luận từng lỗi × model + lỗi khác KẾT LUẬN → disputes.md
#   B4  Tranh luận ĐÚNG 1 vòng (chỉ khi khác kết luận), resume phiên mình → <model>-debate.md
#   B5  Coordinator đọc merged.md + disputes.md (+ debate) và tổng hợp.
# Model hỏng (chưa đăng nhập / hết hạn mức / quá giờ / rỗng) → bỏ, ghi lý do; dưới 2 model → dừng.
# Dùng: review.sh <số PR hoặc URL> ["ghi chú trọng tâm"] [file jira.md]  ·  DRY_RUN=1 → chỉ chuẩn bị dữ liệu
set -euo pipefail
STEP="B0 chuẩn bị"
# Lệnh nào ở cấp script lỗi (gh, git…) cũng in 1 dòng LỖI cho coordinator.
trap 'rc=$?; echo "LỖI ở bước: $STEP (exit $rc${DIR:+, log: $DIR})"' ERR

# ==== Cấu hình ====
# Mặc định ở đây; ghi đè trong file cấu hình riêng mỗi máy (không commit), xem config.example.env:
#   ${CROSS_REVIEW_CONFIG:-~/.config/cross-review/config.env}
CONFIG_FILE="${CROSS_REVIEW_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/cross-review/config.env}"
# shellcheck disable=SC1090
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
CLAUDE_HOME="${CLAUDE_HOME:-}"                     # thư mục cấu hình Claude riêng (CLAUDE_CONFIG_DIR); trống = mặc định
CLAUDE_EXPECT_EMAIL="${CLAUDE_EXPECT_EMAIL:-}"     # có giá trị → Claude phải đăng nhập đúng email này
CLAUDE_MODEL="${CLAUDE_MODEL:-claude-opus-5-5}"; CLAUDE_EFFORT="${CLAUDE_EFFORT:-medium}"   # B1, B3, B4
MERGE_MODEL="${MERGE_MODEL:-claude-sonnet-5-5}"; MERGE_EFFORT="${MERGE_EFFORT:-low}"       # B2, B3.5: chỉ ghép/lọc
CODEX_MODEL="${CODEX_MODEL:-gpt-6.1-sol}";       CODEX_EFFORT="${CODEX_EFFORT:-medium}"
GEMINI_MODEL="${GEMINI_MODEL:-gemini-4-neon-medium}"                                      # agy models để xem tên
# agy headless không hỏi quyền được: lệnh ngoài danh sách này bị chặn và agy dừng cả lượt.
# Chỉ lệnh đọc (không sed/find: có -i, -delete/-exec). Chạy --sandbox --mode auto; account chưa có auto thì
# agy tự về mode mặc định (log: "--mode auto is not available") và chỉ chạy được lệnh trong danh sách này.
AGY_SETTINGS='{"permissions":{"allow":["command(git)","command(cat)","command(head)","command(tail)","command(grep)","command(rg)","command(ls)","command(wc)"]}}'
# Timeout mỗi bước (cú pháp `timeout`: 45m, 900s…). Máy sleep làm stream chết thì CLI treo mãi, timeout cắt nó.
REVIEW_TIMEOUT="${REVIEW_TIMEOUT:-45m}"; MERGE_TIMEOUT="${MERGE_TIMEOUT:-10m}"
CHECK_TIMEOUT="${CHECK_TIMEOUT:-20m}";   DEBATE_TIMEOUT="${DEBATE_TIMEOUT:-15m}"
# ==============================

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
# Công cụ bắt buộc (claude / codex / agy thiếu thì chỉ bỏ model đó)
MISSING=(); for t in git gh jq perl timeout; do command -v "$t" >/dev/null || MISSING+=("$t"); done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "LỖI: thiếu công cụ: ${MISSING[*]} (macOS: brew install gh jq coreutils — coreutils có timeout)"; exit 1
fi
git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "LỖI: chạy trong thư mục git của repo cần review"; exit 1; }
REPO_DIR="$(git rev-parse --show-toplevel)"
PR_ARG="${1:?Thiếu số PR hoặc URL}"
FOCUS="${2:-lỗi logic, vi phạm rule của repo, thiếu test}"
JIRA_FILE="${3:-}"   # file Jira coordinator đã đọc (chỉ khi mô tả PR nhắc tới ticket)
[[ -z "$JIRA_FILE" || -s "$JIRA_FILE" ]] || { echo "LỖI: không đọc được file Jira $JIRA_FILE"; exit 1; }

if [[ "$PR_ARG" =~ github.com/([^/]+/[^/]+)/pull/([0-9]+) ]]; then
  REPO="${BASH_REMATCH[1]}"; N="${BASH_REMATCH[2]}"
else
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"; N="$PR_ARG"
fi
[[ "$N" =~ ^[0-9]+$ ]] || { echo "LỖI: số PR không hợp lệ: $PR_ARG"; exit 1; }
fail() {  # fail <bước> <log> <exit code>
  local why=""; [[ "${3:-}" == 124 || "${3:-}" == 137 ]] && why=" — quá thời gian, có thể máy sleep"
  echo "LỖI ở bước: $1$why (log: $DIR/$2)"; exit 1
}

# ---- B0: lấy diff + file ở PR head (Codex chạy sandbox không có mạng) ----
read -r TITLE_B64 URL BASE HEAD SHA MERGE_OID < <(gh pr view "$N" -R "$REPO" \
  --json title,url,baseRefName,headRefName,headRefOid,mergeCommit \
  -q '[(.title|@base64), .url, .baseRefName, .headRefName, .headRefOid, (.mergeCommit.oid // "-")]|@tsv')
TITLE="$(printf '%s' "$TITLE_B64" | base64 -d)"
DIR="${TMPDIR:-/tmp}/cross-review-$N"
rm -rf "$DIR"; mkdir -p "$DIR/head"
git -C "$REPO_DIR" -c credential.helper= -c credential.helper='!gh auth git-credential' fetch -q origin \
  "+refs/heads/$HEAD:refs/remotes/origin/$HEAD" "+refs/heads/$BASE:refs/remotes/origin/$BASE"
# Diff tính local (gh pr diff lỗi 406 khi PR > 300 file). -M: file chỉ đổi tên/di chuyển (R100)
# không có nội dung diff → tách ra renames.txt, không đưa vào danh sách review.
# PR đã merge: base hiện đã chứa code PR → so với cha thứ nhất của merge commit (base lúc merge).
BASE_REF="origin/$BASE"
if [[ "$MERGE_OID" != "-" ]] && git -C "$REPO_DIR" cat-file -e "$MERGE_OID^1" 2>/dev/null; then BASE_REF="$MERGE_OID^1"; fi
RANGE="$BASE_REF...$SHA"
git -C "$REPO_DIR" diff -M "$RANGE" > "$DIR/pr.diff"
git -C "$REPO_DIR" diff -M --name-status "$RANGE" > "$DIR/name-status.txt"
# File di chuyển mà chỉ đổi dòng cơ học (namespace, use đầu file, docblock rỗng / @group, dòng trống)
# cũng coi là đổi tên. Còn lại → files.txt để review.
MECHANICAL='^[+-]((namespace|use) [^;]+;|[[:space:]]*(/\*\*|\*/|\*|\* @group [[:alnum:]_-]+))?[[:space:]]*$'
: > "$DIR/renames.txt"; : > "$DIR/files.txt"
while IFS=$'\t' read -r st a b; do
  if [[ "$st" == R* ]] && ! git -C "$REPO_DIR" diff -M "$RANGE" -- "$a" "$b" \
       | grep -E '^[+-]' | grep -vE '^(\+\+\+|---) ' | grep -qvE "$MECHANICAL"; then
    echo "$a → $b" >> "$DIR/renames.txt"
  else
    echo "${b:-$a}" >> "$DIR/files.txt"
  fi
done < "$DIR/name-status.txt"
[[ -s "$DIR/name-status.txt" ]] || { echo "LỖI ở bước: B0 chuẩn bị — PR #$N không có thay đổi so với $BASE_REF (log: $DIR)"; exit 1; }
while IFS= read -r f; do
  mkdir -p "$DIR/head/$(dirname "$f")"
  git -C "$REPO_DIR" show "$SHA:$f" > "$DIR/head/$f" 2>/dev/null || rm -f "$DIR/head/$f"   # file bị xoá trong PR
done < "$DIR/files.txt"

# ---- B0: ngữ cảnh PR (mô tả, commit, comment người — bỏ bot, Jira nếu coordinator đưa) → context.md ----
section() { local body; body="$(cat)"; printf '<section name="%s">\n%s\n</section>\n\n' "$1" "${body:-(không có)}"; }
HUMAN='.[] | select(.user.type != "Bot")'
{
  gh pr view "$N" -R "$REPO" --json body -q .body | section "Mô tả PR"
  git -C "$REPO_DIR" log --no-merges --format='- %s%n%b' "$BASE_REF..$SHA" | section "Commit"
  gh api --paginate "repos/$REPO/issues/$N/comments" \
    -q "$HUMAN | \"**\(.user.login)** (\(.created_at[:10])):\n\(.body)\n\"" | section "Comment chung"
  gh api --paginate "repos/$REPO/pulls/$N/reviews" \
    -q "$HUMAN | select(.body != \"\") | \"**\(.user.login)** [\(.state)]:\n\(.body)\n\"" | section "Review"
  gh api --paginate "repos/$REPO/pulls/$N/comments" \
    -q "$HUMAN | \"**\(.user.login)** \`\(.path):\(.line // .original_line)\`\(if .in_reply_to_id then \" (trả lời)\" else \"\" end):\n\(.body)\n\"" \
    | section "Comment inline"
  if [[ -n "${JIRA_FILE:-}" ]]; then section "Jira" < "$JIRA_FILE"; fi
} | perl -CSD -0pe '$_ = substr($_, 0, 40000) . "\n…(cắt bớt)\n" if length > 40000' > "$DIR/context.md"
CONTEXT="$(cat "$DIR/context.md")"

export N TITLE URL BASE HEAD SHA DIR FOCUS CONTEXT
FILES="$(sed 's/^/- /' "$DIR/files.txt")"
RENAMES=$(wc -l < "$DIR/renames.txt" | tr -d ' ')
[[ "$RENAMES" -gt 0 ]] && FILES="$FILES
(+ $RENAMES file chỉ đổi tên/di chuyển, nội dung chỉ đổi namespace/use/docblock @group — danh sách ở $DIR/renames.txt; không review từng file, chỉ kiểm namespace khớp đường dẫn mới và chỗ khác còn tham chiếu tên/đường dẫn cũ)"
export FILES
# Tên model (hiển thị) · ID lỗi · tiền tố file
mid()  { case "$1" in Claude) echo C;; Codex) echo X;; Gemini) echo G;; esac; }
mfile() { echo "$1" | tr '[:upper:]' '[:lower:]'; }
ACTIVE=()          # model còn chạy được
DROPPED=()         # "Model (bước: lý do)"
drop() { DROPPED+=("$1 ($2)"); local a=() m; for m in "${ACTIVE[@]}"; do if [[ "$m" != "$1" ]]; then a+=("$m"); fi; done; ACTIVE=(${a[@]+"${a[@]}"}); }
set_models() {  # cập nhật biến cho prompt theo ACTIVE
  NMODELS=${#ACTIVE[@]}; MODELS="$(IFS=,; echo "${ACTIVE[*]}" | sed 's/,/, /g')"
  local m ids=(); for m in "${ACTIVE[@]}"; do ids+=("$m ($(mid "$m")*)"); done
  MODEL_IDS="$(IFS=,; echo "${ids[*]}" | sed 's/,/, /g')"; export NMODELS MODELS MODEL_IDS
}
need_two() {  # need_two <bước>: dưới 2 model thì dừng
  [[ ${#ACTIVE[@]} -ge 2 ]] && return 0
  echo "LỖI ở bước: $1 — chỉ còn ${#ACTIVE[@]} model (${ACTIVE[*]:-không có}), dừng review. Bỏ: ${DROPPED[*]:-} (log: $DIR)"; exit 1
}
# why <log> <exit code>: đoán lý do hỏng. Chỉ đọc chỗ báo lỗi (stderr + trường lỗi trong JSON),
# không đọc nội dung review — review về đăng nhập/quota không làm báo nhầm.
why() {
  [[ "$2" == 124 || "$2" == 137 ]] && { echo "quá thời gian"; return; }
  local base="${1%.log}" t
  t="$(tail -c 8000 "$1" 2>/dev/null
       jq -r 'select(.is_error == true) | .result // empty' "$base.json" 2>/dev/null
       jq -r 'select(.status != null and .status != "SUCCESS") | tostring' "$base.json" 2>/dev/null
       jq -r 'select(.type == "error" or .type == "turn.failed") | tostring' "$base.jsonl" 2>/dev/null)" || true
  if   grep -qiE 'usage limit|rate.?limit|quota|credit balance|too many requests|\b429\b|out of (tokens|credits)|limit reached' <<<"$t"; then echo "hết hạn mức / token"
  elif grep -qiE 'not logged in|log ?in again|unauthori[sz]ed|\b401\b|token (has )?expired|invalid (api key|token)|authentication (failed|error)' <<<"$t"; then echo "hết hạn đăng nhập"
  elif grep -qiE 'denied_actions|auto-denied|"action":"command"' <<<"$t"; then echo "lệnh bị chặn"
  elif [[ "$2" == 3 ]]; then echo "trả kết quả rỗng"
  else echo "lỗi khác, exit $2"; fi
}

prompt() { ID="${2:-}" perl -0pe 's/\{\{(\w+)\}\}/$ENV{$1}/g' "$SKILL_DIR/prompts/$1.md"; }

[[ "${DRY_RUN:-}" == 1 ]] && { prompt review C > "$DIR/dry-review.md"; echo "DRY_RUN ok: $DIR"; exit 0; }

STEP="B0 kiểm tra đăng nhập"
# ---- Kiểm tra trước khi chạy (không tốn token): model nào chưa đăng nhập thì bỏ ----
# CLAUDE_ENV: thêm CLAUDE_CONFIG_DIR khi có CLAUDE_HOME (dùng qua `env`, chạy được dưới `timeout`)
CLAUDE_ENV=(env); [[ -n "$CLAUDE_HOME" ]] && CLAUDE_ENV+=("CLAUDE_CONFIG_DIR=$CLAUDE_HOME")
CLAUDE_AUTH="$(command -v claude >/dev/null && "${CLAUDE_ENV[@]}" claude auth status 2>/dev/null || true)"
if ! jq -e '.loggedIn == true' <<<"$CLAUDE_AUTH" >/dev/null 2>&1; then
  DROPPED+=("Claude (kiểm tra: chưa cài hoặc chưa đăng nhập)")
elif [[ -n "$CLAUDE_EXPECT_EMAIL" ]] && [[ "$(jq -r '.email // ""' <<<"$CLAUDE_AUTH")" != "$CLAUDE_EXPECT_EMAIL" ]]; then
  DROPPED+=("Claude (kiểm tra: không đăng nhập đúng $CLAUDE_EXPECT_EMAIL)")
else ACTIVE+=(Claude); fi
if command -v codex >/dev/null && codex login status >/dev/null 2>&1; then ACTIVE+=(Codex)
else DROPPED+=("Codex (kiểm tra: chưa đăng nhập)"); fi
if command -v agy >/dev/null && agy models 2>/dev/null | grep -q "^$GEMINI_MODEL"; then ACTIVE+=(Gemini)
else DROPPED+=("Gemini (kiểm tra: agy chưa đăng nhập hoặc không có $GEMINI_MODEL)"); fi
need_two "kiểm tra đăng nhập"

READ_TOOLS=(--allowedTools "Read" "Grep" "Glob" "Bash(git show:*)" "Bash(git log:*)" "Bash(git grep:*)" "Bash(git diff:*)"
            --disallowedTools "Edit" "Write" "NotebookEdit")
# Mọi *_run đọc timeout từ biến T. Thành công → <out> (kết quả) + <out>.sid (phiên để resume).
# claude_run <out> <prompt> [thêm tham số...]
claude_run() {
  local out="$1" p="$2"; shift 2
  (cd "$REPO_DIR" && timeout -k 30 "$T" "${CLAUDE_ENV[@]}" claude -p "$p" --strict-mcp-config \
     --add-dir "$DIR" --output-format json "$@" > "$out.json" 2> "$out.log") || return
  jq -e '(.is_error | not) and ((.result // "") | test("\\S"))' "$out.json" > /dev/null || return 3
  jq -r '.result' "$out.json" > "$out"; jq -r '.session_id' "$out.json" > "$out.sid"
}
# codex_run <out> <prompt> [session id để resume] [effort]
codex_run() {
  local out="$1" p="$2" sid="${3:-}" effort="${4:-$CODEX_EFFORT}"
  if [[ -z "$sid" ]]; then
    timeout -k 30 "$T" codex exec -C "$REPO_DIR" --sandbox read-only -m "$CODEX_MODEL" \
      -c model_reasoning_effort="$effort" --json -o "$out" "$p" > "$out.jsonl" 2> "$out.log" || return
    jq -r 'select(.type=="thread.started").thread_id' "$out.jsonl" > "$out.sid"
  else
    (cd "$REPO_DIR" && timeout -k 30 "$T" codex exec resume "$sid" -m "$CODEX_MODEL" -c sandbox_mode=read-only \
      -c model_reasoning_effort="$effort" -o "$out" "$p" > "$out.log" 2>&1) || return
    echo "$sid" > "$out.sid"
  fi
  grep -q '[^[:space:]]' "$out" 2>/dev/null || return 3
}
# gemini_run <out> <prompt> [conversation id] — agy chỉ đọc: --sandbox --mode auto (tự duyệt quyền)
# + AGY_SETTINGS cho sẵn lệnh đọc. Rỗng / lệnh bị chặn → chạy lại 1 lần kèm lời nhắc.
gemini_once() {
  local out="$1" p="$2" sid="${3:-}" extra=()
  [[ -n "$sid" ]] && extra=(--conversation "$sid")
  (cd "$REPO_DIR" && timeout -k 30 "$T" agy -p "$p$(prompt gemini-tools)" --model "$GEMINI_MODEL" --output-format json \
     --sandbox --mode auto --add-dir "$DIR" --settings "$AGY_SETTINGS" ${extra[@]+"${extra[@]}"} \
     > "$out.json" 2>> "$out.log") || return
  jq -c '.denied_actions // empty' "$out.json" >> "$out.log"
  jq -e '.status == "SUCCESS" and ((.response // "") | test("\\S")) and ((.denied_actions // []) | length == 0)' \
    "$out.json" > /dev/null || return 3
  jq -r '.response' "$out.json" > "$out"; jq -r '.conversation_id' "$out.json" > "$out.sid"
}
gemini_run() {
  local out="$1" p="$2" sid="${3:-}" rc=0
  : > "$out.log"
  gemini_once "$out" "$p" "$sid" && return 0 || rc=$?
  [[ "$rc" == 3 ]] || return "$rc"
  echo "--- lần 1 hỏng (rỗng hoặc lệnh bị chặn), chạy lại" >> "$out.log"
  gemini_once "$out" "$p

LƯU Ý: lần trước một lệnh shell của em bị chặn nên phiên dừng giữa chừng. Đọc file bằng tool đọc file,
shell chỉ dùng git/cat/head/tail/grep/rg/ls/wc (không pipe), và phải in đủ kết quả cuối." "$sid"
}
# run_model <model> <out> <prompt> [sid để resume]
run_model() {
  case "$1" in
    Claude) if [[ -n "${4:-}" ]]; then claude_run "$2" "$3" --resume "$4" --model "$CLAUDE_MODEL" --effort "$CLAUDE_EFFORT" "${READ_TOOLS[@]}"
            else claude_run "$2" "$3" --model "$CLAUDE_MODEL" --effort "$CLAUDE_EFFORT" "${READ_TOOLS[@]}"; fi ;;
    Codex)  codex_run "$2" "$3" "${4:-}" ;;
    Gemini) gemini_run "$2" "$3" "${4:-}" ;;
  esac
}
# run_step <tên bước> <hậu tố file: "" | -check | -debate> <timeout> <bỏ model hỏng: 1|0> <hàm tạo prompt> <hàm lấy sid>
# Chạy song song mọi model trong ACTIVE. Model hỏng → bỏ (1) hoặc chỉ ghi chú (0).
run_step() {
  local step="$1" suf="$2" t="$3" dropfail="$4" mkp="$5" getsid="$6" m pids=() names=() i rc
  for m in "${ACTIVE[@]}"; do
    T=$t run_model "$m" "$DIR/$(mfile "$m")$suf.md" "$($mkp "$m")" "$($getsid "$m")" & pids+=($!); names+=("$m")
  done
  for i in "${!pids[@]}"; do
    m="${names[$i]}"; rc=0; wait "${pids[$i]}" || rc=$?
    if [[ "$rc" == 0 ]]; then continue; fi
    local reason; reason="$(why "$DIR/$(mfile "$m")$suf.md.log" "$rc")"
    if [[ "$dropfail" == 1 ]]; then drop "$m" "$step: $reason"
    else DROPPED+=("$m ($step: $reason — giữ kết luận recheck)"); DEBATE_FAILED+=("$m"); fi
  done
}
# Bước gộp/lọc (rẻ, không tool): Claude Sonnet nếu Claude còn, không thì Codex effort low, cuối cùng Gemini.
cheap_run() {  # cheap_run <out> <prompt>
  if   in_active Claude; then T=$MERGE_TIMEOUT claude_run "$1" "$2" --model "$MERGE_MODEL" --effort "$MERGE_EFFORT" --tools ""
  elif in_active Codex;  then T=$MERGE_TIMEOUT codex_run "$1" "$2" "" low
  else T=$MERGE_TIMEOUT gemini_run "$1" "$2"; fi
}
in_active() { local m; for m in "${ACTIVE[@]}"; do if [[ "$m" == "$1" ]]; then return 0; fi; done; return 1; }
no_sid() { :; }
review_prompt() { prompt review "$(mid "$1")"; }

STEP="B1 review"
# ---- B1: review độc lập, song song ----
DEBATE_FAILED=()
run_step "B1 review" "" "$REVIEW_TIMEOUT" 1 review_prompt no_sid
need_two "B1 review"
set_models

STEP="B2 gộp"
# ---- B2: gộp + ghi ai tìm (1 lần gọi rẻ, không tool) ----
MERGE_PROMPT="$(prompt merge)"
for m in "${ACTIVE[@]}"; do MERGE_PROMPT="$MERGE_PROMPT

=== $m ($(mid "$m")*) ===
$(cat "$DIR/$(mfile "$m").md")"; done
cheap_run "$DIR/merged.md" "$MERGE_PROMPT" || fail "B2 gộp" merged.md.log $?

STEP="B3 recheck"
# ---- B3: recheck toàn bộ danh sách gộp, mỗi model resume phiên B1 của chính mình ----
CHECK_PROMPT="$(prompt recheck)

$(cat "$DIR/merged.md")"
check_prompt() { echo "$CHECK_PROMPT"; }
b1_sid() { cat "$DIR/$(mfile "$1").md.sid" 2>/dev/null; }
run_step "B3 recheck" "-check" "$CHECK_TIMEOUT" 1 check_prompt b1_sid
need_two "B3 recheck"
set_models

STEP="B3.5 lọc bất đồng"
# ---- B3.5: bảng kết luận + lọc lỗi khác KẾT LUẬN (khác mức thì coordinator tự quyết) ----
DISPUTE_PROMPT="$(prompt disputes)

=== Danh sách gộp ===
$(cat "$DIR/merged.md")"
for m in "${ACTIVE[@]}"; do DISPUTE_PROMPT="$DISPUTE_PROMPT

=== $m recheck ===
$(cat "$DIR/$(mfile "$m")-check.md")"; done
cheap_run "$DIR/disputes.md" "$DISPUTE_PROMPT" || fail "B3.5 lọc bất đồng" disputes.md.log $?

FILES_OUT="merged.md, disputes.md"   # disputes.md có bảng kết luận; <model>-check.md chỉ đọc khi cần
summary() {
  local s="Model: ${ACTIVE[*]}"
  if [[ ${#DROPPED[@]} -gt 0 ]]; then s="$s · Bỏ/lỗi: $(IFS=';'; echo "${DROPPED[*]}")"; fi
  echo "$s" > "$DIR/models.md"; echo "$s"
}
if grep -q "KHÔNG CÓ BẤT ĐỒNG" "$DIR/disputes.md"; then
  echo "XONG: $DIR ($FILES_OUT — không có bất đồng, bỏ qua B4) · $(summary)"; exit 0
fi

STEP="B4 tranh luận"
# ---- B4: tranh luận đúng 1 vòng; model nào lỗi thì giữ kết luận recheck của nó ----
debate_prompt() { prompt debate "$1"; echo; echo; cat "$DIR/disputes.md"; }
check_sid() { cat "$DIR/$(mfile "$1")-check.md.sid" 2>/dev/null; }
run_step "B4 tranh luận" "-debate" "$DEBATE_TIMEOUT" 0 debate_prompt check_sid
for m in "${ACTIVE[@]}"; do
  in_list=0; for f in ${DEBATE_FAILED[@]+"${DEBATE_FAILED[@]}"}; do if [[ "$f" == "$m" ]]; then in_list=1; fi; done
  if [[ "$in_list" == 0 ]]; then FILES_OUT="$FILES_OUT, $(mfile "$m")-debate.md"; fi
done
echo "XONG: $DIR ($FILES_OUT) · $(summary)"
