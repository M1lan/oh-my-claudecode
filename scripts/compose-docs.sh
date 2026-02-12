#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

DOCS_DIR="${PROJECT_DIR}/docs"
PARTIALS_DIR="${DOCS_DIR}/partials"
SHARED_DIR="${DOCS_DIR}/shared"
TEMPLATES_DIR="${DOCS_DIR}/templates"

# Ensure directories exist
mkdir -p "${PARTIALS_DIR}" "${SHARED_DIR}"

# ── process_template: replace {{INCLUDE:path}} with file contents ────────────
process_template() {
  local input_file="$1"
  local output_file="$2"
  local content
  content=$(<"${input_file}")

  while [[ "${content}" =~ \{\{INCLUDE:([^}]+)\}\} ]]; do
    local include_path="${BASH_REMATCH[1]}"
    local include_content
    include_content=$(<"${include_path}") || {
      echo "ERROR: Cannot include ${include_path}" >&2
      return 1
    }
    content="${content//"{{INCLUDE:${include_path}}}"/"${include_content}"}"
  done

  printf '%s\n' "${content}" > "${output_file}"
}

# ── Copy partials to shared/ for direct reference by skills ─────────────────
if [[ -d "${PARTIALS_DIR}" ]]; then
  partial_count=0
  while IFS= read -r -d '' partial_file; do
    filename="$(basename "${partial_file}")"
    cp "${partial_file}" "${SHARED_DIR}/${filename}"
    (( partial_count++ )) || true
  done < <(find "${PARTIALS_DIR}" -maxdepth 1 -name "*.md" -print0 | sort -z)
  echo "Synced ${partial_count} partials to shared/"
fi

# ── Process template files from docs/templates/*.template.md ─────────────────
if [[ -d "${TEMPLATES_DIR}" ]]; then
  template_count=0
  while IFS= read -r -d '' template_file; do
    filename="$(basename "${template_file}")"
    # Strip .template from the output filename: foo.template.md -> foo.md
    output_name="${filename/.template/}"
    output_file="${DOCS_DIR}/${output_name}"

    echo "Processing ${filename} -> ${output_name}"
    process_template "${template_file}" "${output_file}"
    (( template_count++ )) || true
  done < <(find "${TEMPLATES_DIR}" -maxdepth 1 -name "*.template.md" -print0 | sort -z)

  if [[ "${template_count}" -gt 0 ]]; then
    echo "Processed ${template_count} template(s)"
  fi
fi

echo "Documentation composition complete."
