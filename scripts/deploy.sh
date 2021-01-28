# Deployment happens semi-automatic for now. The deployment package is uploaded
# to ~/deploy on the server and is then manually swapped via ssh.

pwd

# Build the backend in releas mode
cd backend
cargo build --release
cd ..

# Build typescript from the frondend. Elm was already build previously.
tsc

# Prepare
ssh ./scripts/deployment-key.pem pacosako@pacoplay.com "rm -Rf ~/deploy; mkdir deploy; mkdir deploy/backend; mkdir deploy/target"

# Backend
scp -C ./backend/target/release/pacosako-tool-server pacosako@pacoplay.com:~/deploy/backend/pacosako
scp -C ./backend/Rocket.toml pacosako@pacoplay.com:~/deploy

# Frontend
cp frontend/static/* target/
scp -C ./target/* pacosako@pacoplay.com:~/deploy/target


# Note that the database from ~/deploy/backend/data is not copied over,
# that one does not get redeployed.
