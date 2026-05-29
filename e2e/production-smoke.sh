#!/usr/bin/env bash
# MCPFind production smoke suite — 10 critical-path flows
# Run: bash e2e/production-smoke.sh
# Target: https://mcpfind.org (production only, not localhost)
# Added: 2026-05-28

set -euo pipefail

BASE="https://mcpfind.org"
PASS=0
FAIL=0
FAILURES=()

# ── helpers ─────────────────────────────────────────────────────────────────

pass() { echo "PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL  $1 — $2"; FAIL=$((FAIL + 1)); FAILURES+=("$1: $2"); }

http_status() { curl -s -o /dev/null -w "%{http_code}" "$1"; }
fetch()       { curl -s "$1"; }

assert_status() {
  local name="$1" url="$2" expected="$3"
  local actual
  actual=$(http_status "$url")
  if [[ "$actual" == "$expected" ]]; then
    pass "$name (HTTP $actual)"
  else
    fail "$name" "expected HTTP $expected, got $actual (URL: $url)"
  fi
}

assert_contains() {
  local name="$1" body="$2" needle="$3"
  # Use bash substring match to avoid SIGPIPE from grep -q on large bodies
  if [[ "$body" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name" "expected to find: '$needle'"
  fi
}

assert_not_contains() {
  local name="$1" body="$2" needle="$3"
  if [[ "$body" == *"$needle"* ]]; then
    fail "$name" "found forbidden string: '$needle'"
  else
    pass "$name"
  fi
}

assert_count_gte() {
  local name="$1" body="$2" needle="$3" min="$4"
  local count
  # Write to temp file to avoid SIGPIPE on grep | wc with large bodies
  local tmpfile
  tmpfile=$(mktemp)
  printf '%s' "$body" > "$tmpfile"
  count=$(grep -oF "$needle" "$tmpfile" | wc -l | tr -d ' ') || count=0
  rm -f "$tmpfile"
  if [[ "$count" -ge "$min" ]]; then
    pass "$name (count=$count >= $min)"
  else
    fail "$name" "expected >= $min occurrences of '$needle', got $count"
  fi
}

# ── Flow 1: Homepage ─────────────────────────────────────────────────────────
echo ""
echo "── Flow 1: Homepage ────────────────────────────────────────────────────"
F1=$(fetch "$BASE/")
assert_status "F1.1 homepage HTTP 200"           "$BASE/"         "200"
assert_contains "F1.2 title contains MCPFind"     "$F1"            "MCPFind"
assert_contains "F1.3 meta description present"   "$F1"            'name="description"'
assert_contains "F1.4 server count > 0 in description" "$F1"      "3,274"
assert_contains "F1.5 /servers category nav link" "$F1"            'href="/servers?category=devtools"'

# ── Flow 2: HEALTHY server detail page ───────────────────────────────────────
echo ""
echo "── Flow 2: HEALTHY server detail (io-github-netdata-mcp-server) ────────"
SLUG_HEALTHY="io-github-netdata-mcp-server"
F2=$(fetch "$BASE/servers/$SLUG_HEALTHY")
assert_status "F2.1 HTTP 200"                          "$BASE/servers/$SLUG_HEALTHY"   "200"
assert_contains "F2.2 canonical absolute URL"          "$F2"  "canonical\" href=\"https://mcpfind.org/servers/$SLUG_HEALTHY\""
assert_contains "F2.3 og:title present"                "$F2"  'og:title" content='
assert_contains "F2.4 VerifiedServerBadge renders"     "$F2"  "VerifiedServerBadge"
assert_contains "F2.5 Verified text visible"           "$F2"  "<span>Verified</span>"
assert_not_contains "F2.6 no noindex"                 "$F2"  "noindex"
assert_not_contains "F2.7 no doubled aria-label"      "$F2"  "Verified active: Verified active:"

# ── Flow 3: STALE server detail page ─────────────────────────────────────────
echo ""
echo "── Flow 3: STALE server detail (io-github-sellisd-mcp-units) ───────────"
SLUG_STALE="io-github-sellisd-mcp-units"
F3=$(fetch "$BASE/servers/$SLUG_STALE")
assert_status "F3.1 HTTP 200"                         "$BASE/servers/$SLUG_STALE"  "200"
assert_contains "F3.2 StaleServerBadge chunk ref"     "$F3"  "StaleServerBadge"
assert_contains "F3.3 outdated text visible"          "$F3"  "outdated"
assert_contains "F3.4 canonical absolute URL"         "$F3"  "rel=\"canonical\" href=\"https://mcpfind.org/servers/$SLUG_STALE\""

# ── Flow 4: Deleted slug → 404 ───────────────────────────────────────────────
echo ""
echo "── Flow 4: Deleted slug → 404 ──────────────────────────────────────────"
SLUG_DELETED="ai-smithery-mistersandfr-supabase-mcp-selfhosted"
assert_status "F4.1 deleted slug HTTP 404"  "$BASE/servers/$SLUG_DELETED"  "404"

# ── Flow 5: Category page (devtools) ─────────────────────────────────────────
echo ""
echo "── Flow 5: Category page /categories/devtools ───────────────────────────"
F5=$(fetch "$BASE/categories/devtools")
assert_status "F5.1 HTTP 200"                              "$BASE/categories/devtools"  "200"
assert_contains "F5.2 RelatedServersForCategory renders"   "$F5"  "related-server"
assert_contains "F5.3 data-conversion attribute present"   "$F5"  "data-conversion"
assert_contains "F5.4 VerifiedServerBadge visible"         "$F5"  "Verified"
assert_contains "F5.5 StaleServerBadge visible (outdated)" "$F5"  "outdated"

# ── Flow 6: Listicle blog post ────────────────────────────────────────────────
echo ""
echo "── Flow 6: Listicle blog — best-devtools-mcp-servers-repo-intelligence ──"
LISTICLE_SLUG="best-devtools-mcp-servers-repo-intelligence"
F6=$(fetch "$BASE/blog/$LISTICLE_SLUG")
assert_status "F6.1 HTTP 200"                              "$BASE/blog/$LISTICLE_SLUG"  "200"
# JSON-LD: 2 <script> tags but contain 5+ @type entries (Article, FAQPage, HowTo, BreadcrumbList, BlogPosting)
assert_count_gte "F6.2 JSON-LD script blocks >= 2"        "$F6"  "application/ld+json"  2
assert_count_gte "F6.2b JSON-LD @type entries >= 5"       "$F6"  '"@type"'  5
assert_contains "F6.3 Next Steps H2 present"              "$F6"  'id="next-steps"'
assert_contains "F6.4 Related Servers section present"    "$F6"  'id="related-servers-in-this-category"'
# RSC payload encodes hrefs without HTML quotes — match both patterns
assert_count_gte "F6.5 server hrefs >= 6"                 "$F6"  '/servers/'  6
assert_contains "F6.6 blog_to_servers_click attribute"    "$F6"  "blog_to_servers_click"

# ── Flow 7: Sitemap ───────────────────────────────────────────────────────────
echo ""
echo "── Flow 7: Sitemap ─────────────────────────────────────────────────────"
F7=$(fetch "$BASE/sitemap.xml")
assert_status "F7.1 sitemap.xml HTTP 200"                  "$BASE/sitemap.xml"             "200"
assert_contains "F7.2 sitemap-servers-0.xml referenced"    "$F7"  "sitemap-servers-0.xml"
assert_not_contains "F7.3 sitemap-servers-1.xml absent"    "$F7"  "sitemap-servers-1.xml"
assert_status "F7.4 sitemap-servers-0.xml HTTP 200"        "$BASE/sitemap-servers-0.xml"   "200"
assert_status "F7.5 sitemap-servers-1.xml HTTP 404"        "$BASE/sitemap-servers-1.xml"   "404"
# Server count in sitemap should be ~3,274 (within ±100 of Supabase count)
F7_S0=$(fetch "$BASE/sitemap-servers-0.xml")
SITEMAP_COUNT=$(echo "$F7_S0" | grep -c "<loc>" || true)
if [[ "$SITEMAP_COUNT" -ge 3000 && "$SITEMAP_COUNT" -le 4000 ]]; then
  pass "F7.6 sitemap server count in expected range ($SITEMAP_COUNT entries)"
else
  fail "F7.6 sitemap server count" "expected 3000-4000, got $SITEMAP_COUNT"
fi

# ── Flow 8: Search ───────────────────────────────────────────────────────────
echo ""
echo "── Flow 8: Search — /servers?q=github ──────────────────────────────────"
F8=$(fetch "$BASE/servers?q=github")
assert_status "F8.1 search page HTTP 200"           "$BASE/servers?q=github"  "200"
assert_contains "F8.2 page title present"           "$F8"  "<title>"
assert_count_gte "F8.3 server links >= 1"           "$F8"  'href="/servers/'  1

# ── Flow 9: Privacy + GA4 ────────────────────────────────────────────────────
echo ""
echo "── Flow 9: Privacy page + GA4 events ───────────────────────────────────"
F9=$(fetch "$BASE/privacy")
assert_status "F9.1 privacy page HTTP 200"                   "$BASE/privacy"  "200"
assert_contains "F9.2 GA4 measurement ID present"            "$F9"  "G-LLD1VR2K5Z"
assert_contains "F9.3 submit_form_completed event listed"     "$F9"  "submit_form_completed"
assert_contains "F9.4 blog_to_servers_click event listed"     "$F9"  "blog_to_servers_click"
assert_contains "F9.5 server_outbound_click event listed"     "$F9"  "server_outbound_click"
assert_contains "F9.6 directory_search_used event listed"     "$F9"  "directory_search_used"

# ── Flow 10: No doubled aria-label ───────────────────────────────────────────
echo ""
echo "── Flow 10: No doubled aria-label (cross-page verification) ─────────────"
# Check the HEALTHY page again and also a second HEALTHY server to be thorough
SLUG2="io-github-tldraw-tldraw"
F10=$(fetch "$BASE/servers/$SLUG2")
assert_status "F10.1 second HEALTHY server HTTP 200"          "$BASE/servers/$SLUG2"  "200"
assert_not_contains "F10.2 no doubled prefix on server 2"     "$F10"  "Verified active: Verified active:"
assert_contains "F10.3 correct single aria-label format"      "$F10"  "aria-label=\"Verified active:"

# ── Summary ──────────────────────────────────────────────────────────────────
TOTAL=$((PASS + FAIL))
echo ""
echo "════════════════════════════════════════════════════"
echo "Results: $PASS/$TOTAL passed"
if [[ ${#FAILURES[@]} -gt 0 ]]; then
  echo ""
  echo "Failures:"
  for f in "${FAILURES[@]}"; do
    echo "  - $f"
  done
  echo ""
  exit 1
else
  echo "All checks passed."
fi
