# Takes the deployment and replaces the staging server.

# Shut down staging server
screen -X -S stage quit

# Remove existing deployment
rm -r ~/stage

# Install deployment to staging
cp -r ~/deploy ~/stage

# Restart staging server
screen -S stage -m -d ./run-stage.sh