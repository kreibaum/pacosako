# Deployment happens semi-automatic for now. The deployment package is uploaded
# to ~/deploy on the server and is then manually swapped via ssh.

pwd

# Build the backend in releas mode
cd backend
cargo build --release
cd ..

# Build typescript from the frontend. Elm was already build previously.
tsc

# minimize javascript
uglifyjs ./target/elm.js -o ./target/elm.min.js --mangle --compress
uglifyjs ./target/main.js -o ./target/main.min.js --mangle --compress

# Prepare
ssh pacosako@pacoplay.com "rm -Rf ~/deploy; mkdir deploy; mkdir deploy/backend; mkdir deploy/target"

# Backend
scp -C ./backend/target/release/pacosako-tool-server pacosako@pacoplay.com:~/deploy/backend/pacosako

# Frontend
cp frontend/static/* target/
scp -C ./target/* pacosako@pacoplay.com:~/deploy/target


# Note that the database from ~/deploy/backend/data is not copied over,
# that one does not get redeployed.
