#!/usr/bin/env bash
set -eo pipefail
export OP_SESSION="${OP_SESSION?Please define OP_SESSION}"
export OP_ACCOUNT="${OP_ACCOUNT:-my}"

usage() {
  cat <<-USAGE
$(basename "$0") [file]
Updates tags for a bunch of 1Password items in one go.

OPTIONS

  [file]        The path to items in 1Password to update, in YAML format.
                Each item in the file must contain the tags they will
                be updated with

ENVIRONMENT VARIABLES

  OP_ACCOUNT    The 1Password account within which the passwords provided
                with the file are hosted.
                (Default: $OP_ACCOUNT)

  OP_SESSION    A 1Password CLI session key.


NOTES

- Run the command to generate the YAML file that you'll eventually update.
  You would provide "~/Downloads/1password-entries.yaml" to $(basename "$0") to perform
  the update:

  \`\`\`sh
  op-cli item list --format json |
    yq -o=yaml -P '.[] |= pick(["title", "tags", "vault"])' |
    tee ~/Downloads/1password-entries.yaml
  \`\`\`
USAGE
}
if grep -Eq -- '-h|--help' <<< "$@"
then
  usage
  exit 0
fi
file="$1"
if test -z "$file"
then
  usage
  >&2 echo "ERROR: YAML file of passwords to update not provided."
  exit 1
fi
cache="${TMPDIR:-/tmp}/1pass_bulk_update_cache"
timestamp_fmt='%Y-%m-%d %H:%M:%S'
yq_query='.[] |
  select (.title != "") |
  (select((.tags | length) > 0) // {"tags":["none"]}) |
  (.title | @base64) + "&&&" + ((.tags | @csv) | @base64) + "&&&" + (.vault.id | @base64)'
while read -u 3 -r entry
do
  title_enc=$(sed -E 's/\&{3}/\n/g' <<< "$entry" | head -1)
  tags_enc=$(sed -E 's/\&{3}/\n/g' <<< "$entry" | head -2 | head -1)
  vault_enc=$(sed -E 's/\&{3}/\n/g' <<< "$entry" | head -3 | tail -1)
  title=$(base64 -d <<< "$title_enc")
  tags=$(base64 -d <<< "$tags_enc")
  vault=$(base64 -d <<< "$vault_enc")
  log_line="[$(date +"$timestamp_fmt")] operation: %s, title: [$title], vault: [$vault], new_tags: [$tags]\n"
  if { test -f "$cache" && grep -q "$title_enc" "$cache"; }
  then
    # shellcheck disable=SC2059
    >&2 printf "$log_line" "skip"
    continue
  fi
  # shellcheck disable=SC2059
  >&2 printf "$log_line" "update"
  $(which op) item edit "$title" \
    --session "$OP_SESSION" \
    --account "$OP_ACCOUNT" \
    --vault "$vault" \
    --tags "$tags" >/dev/null || true
  echo "$title_enc" >> "$cache"
done 3< <(yq "$yq_query" "$file")
