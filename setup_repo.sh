set -euo pipefail

# Show nested repositories that must not be included.
echo "Nested repositories being excluded:"
find . -mindepth 2 -type d -name .git -prune -printf '%h\n'

# Back up the existing ignore file.
touch .gitignore
cp .gitignore .gitignore.backup

# Add every nested Git repository to .gitignore.
{
    echo
    echo "# Nested source repositories — managed separately"
    find . -mindepth 2 -type d -name .git -prune -printf '%h\n' \
        | sed 's#^\./#/#; s#$#/#' \
        | sort -u
} >> .gitignore

# Remove duplicate ignore entries.
awk '!seen[$0]++' .gitignore > .gitignore.tmp
mv .gitignore.tmp .gitignore

echo
echo "Effective nested-repository exclusions:"
grep -E '^/.+/$' .gitignore
