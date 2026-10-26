#!/usr/bin/env bash
# A small, made-up project with some history, for `git status`, `git log`
# and an agent to work on in demos. Fixed author and dates, so every build
# looks the same.
set -euo pipefail

export GIT_AUTHOR_NAME="Demo Dev" GIT_AUTHOR_EMAIL="dev@example.com"
export GIT_COMMITTER_NAME="Demo Dev" GIT_COMMITTER_EMAIL="dev@example.com"

mkdir -p ~/shop-api/app ~/shop-api/tests
cd ~/shop-api
git init -q -b main

commit() {
  export GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1"
  git add -A
  git commit -q -m "$2"
}

cat > README.md <<'EOF'
# shop-api

A tiny product catalogue API used for demos.
EOF
cat > app/products.py <<'EOF'
PRODUCTS = [{"id": i, "name": f"Product {i}"} for i in range(1, 121)]


def list_products():
    return PRODUCTS
EOF
commit "2026-10-01T09:12:00" "Start the catalogue API"

cat > app/products.py <<'EOF'
PRODUCTS = [{"id": i, "name": f"Product {i}"} for i in range(1, 121)]


def list_products(page=1, limit=50):
    """One page of products. Pages start at 1."""
    start = (page - 1) * limit
    return PRODUCTS[start:start + limit]
EOF
commit "2026-10-03T14:40:00" "Paginate the product list"

cat > tests/test_products.py <<'EOF'
from app.products import list_products


def test_first_page_has_fifty_products():
    assert len(list_products()) == 50


def test_last_page_is_partial():
    assert len(list_products(page=3)) == 20
EOF
commit "2026-10-04T11:05:00" "Test the first and last pages"

cat > app/health.py <<'EOF'
def health():
    return {"status": "ok"}
EOF
commit "2026-10-06T16:22:00" "Add a health check"

# Leave one change uncommitted, so `git status` has something to show.
printf '\n## Running\n\n    python3 -m pytest\n' >> README.md
