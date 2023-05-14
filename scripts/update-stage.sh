# Takes the deployment and replaces the staging server.

# Stop staging server
sudo systemctl stop stage

# Remove existing deployment
rm -r ~/stage

# Ensure the directory exists
mkdir -p ~/stage

# Install deployment to staging
tar -zxf deploy.tar.gz -C ~/stage

# Start staging server
sudo systemctl start stage
