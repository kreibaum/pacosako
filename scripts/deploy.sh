# Deployment happens semi-automatic for now. The deployment package is uploaded
# to ~/deploy on the server and is then manually swapped via ssh.

pwd

cd backend
cargo build --release
cd ..

# Prepare
ssh -i ./scripts/deployment-key.pem ubuntu@ec2-3-15-154-181.us-east-2.compute.amazonaws.com "rm -Rf ~/deploy; mkdir deploy; mkdir deploy/backend; mkdir deploy/target"

# Backend
scp -i ./scripts/deployment-key.pem ./backend/target/release/pacosako-tool-server ubuntu@ec2-3-15-154-181.us-east-2.compute.amazonaws.com:~/deploy/backend/pacosako
scp -i ./scripts/deployment-key.pem ./backend/Rocket.toml ubuntu@ec2-3-15-154-181.us-east-2.compute.amazonaws.com:~/deploy

# Frontend
cp frontend/static/* target/
scp -i ./scripts/deployment-key.pem ./target/* ubuntu@ec2-3-15-154-181.us-east-2.compute.amazonaws.com:~/deploy/target


# Note that the database from ~/deploy/backend/data is not copied over,
# that one does not get redeployed.
