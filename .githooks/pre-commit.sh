# Add this via
# git config --local core.hooksPath .githooks/
# https://github.com/zed-industries/zed/discussions/6606#discussioncomment-12335433

git diff-index --name-status --cached HEAD -- | cut -c3- | while read FILE; do
    if git diff --cached "$FILE" | grep -q "BOOKMARK"; then
        echo $FILE ' contains a BOOKMARK string!'
        exit 1
    fi
done
