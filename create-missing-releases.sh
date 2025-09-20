#!/bin/bash
# Script to create missing GitHub releases for existing tags

echo "Creating missing GitHub Releases..."

# Array of versions and their descriptions
declare -A releases=(
    ["v25.0.31"]="Bug fixes and improvements"
    ["v25.0.32"]="Stability improvements"
    ["v25.0.33"]="Performance optimizations"
    ["v25.0.34"]="Bug fixes"
    ["v25.0.35"]="Minor updates"
    ["v25.0.36"]="Dependency updates"
    ["v25.0.37"]="Configuration improvements"
    ["v25.0.38"]="Home Assistant integration"
    ["v25.0.39"]="GitHub Actions rate limiting fixes"
    ["v25.0.40"]="Testing improvements"
    ["v25.0.41"]="Build process updates"
    ["v25.0.42"]="Docker Hub configuration"
    ["v25.0.43"]="Pre-kill switch release"
)

for version in "${!releases[@]}"; do
    description="${releases[$version]}"

    echo "Creating release for $version..."

    # Check if release already exists
    if gh release view "$version" &>/dev/null; then
        echo "  Release $version already exists, skipping..."
        continue
    fi

    # Get the tag date
    tag_date=$(git log -1 --format=%ai "$version" 2>/dev/null | cut -d' ' -f1)

    # Create the release
    gh release create "$version" \
        --title "$version - $description" \
        --notes "## $description

### Docker Image
\`\`\`bash
docker pull magicalyak/nzbgetvpn:$version
\`\`\`

### Changes
See commit history for detailed changes.

**Full Changelog**: https://github.com/magicalyak/nzbgetvpn/compare/$(git describe --tags --abbrev=0 $version^)...$version" \
        --prerelease

    echo "  Created release for $version"
    sleep 1 # Be nice to GitHub API
done

echo "Done creating releases!"
echo ""
echo "Latest releases:"
gh release list --limit 5