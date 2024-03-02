# This is a utility script to help me improve the translation on a local
# version of the website. This updates the Elm code every time the json
# changes and then elm-live hot reloads the frontend.

# Alternatively, rewrite this with https://watchexec.github.io/
# watchexec --exts json -- pytrans.py
# Problem is, that then you need to have watchexec installed,
# which increases my dependency count again.

file_to_watch="/home/rolf/dev/pacosako/frontend/i18n/Esperanto.json"
command_to_run="/home/rolf/dev/bin/pytrans.py"

echo "Watching file '$file_to_watch' for changes."
pwd

inotifywait -m -e modify "$file_to_watch" |
while read -r path action file; do
    echo "File '$file' at path '$path' was modified. Running command."
    $command_to_run
done
