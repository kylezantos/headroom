# Shared codesign identity selection for build-app.sh and release-app.sh.
#
# Renewing a certificate leaves two valid identities with the same display name (the
# Developer ID G2 replacement, 2026-10-04). codesign rejects a name that matches more
# than one identity as ambiguous, so callers sign with the SHA-1 this returns instead.

# Prints the SHA-1 of the valid codesigning identity whose name starts with $1 and whose
# certificate expires last. Prints nothing when no identity matches.
headroom_newest_identity_sha() {
  local prefix="$1"
  local identities sha expiry epoch best_sha="" best_epoch=0

  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  while read -r sha; do
    [[ -n "${sha}" ]] || continue
    expiry="$(security find-certificate -a -Z -p -c "${prefix}" 2>/dev/null \
      | awk -v want="${sha}" '
          /^SHA-1 hash:/ { keep = ($3 == want) }
          keep && /-----BEGIN CERTIFICATE-----/ { printing = 1 }
          keep && printing { print }
          keep && /-----END CERTIFICATE-----/ { exit }
        ' \
      | openssl x509 -noout -enddate 2>/dev/null \
      | sed 's/^notAfter=//')"
    epoch="$(date -j -f '%b %e %T %Y %Z' "${expiry}" '+%s' 2>/dev/null || echo 0)"
    if [[ -z "${best_sha}" || "${epoch}" -gt "${best_epoch}" ]]; then
      best_sha="${sha}"
      best_epoch="${epoch}"
    fi
  done < <(printf '%s\n' "${identities}" \
    | awk -v prefix="\"${prefix}" 'index($0, prefix) { print $2 }')

  printf '%s' "${best_sha}"
}

# Prints the display name of the identity with SHA-1 $1.
headroom_identity_name_for_sha() {
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -v want="$1" '$2 == want { sub(/^[^"]*"/, ""); sub(/".*$/, ""); print; exit }'
}
