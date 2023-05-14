# Takes the staging server and replaces the production server.

# Shut down production server
sudo systemctl stop prod

# Makes a backup of the prod server
cp -r ~/prod ~/prod-backup

# Makes a backup of the prod database
cp ~/db/prod.sqlite ~/db/backup/$(date +"%Y-%m-%d;%H:%M").sqlite

# Remove existing deployment
rm -r ~/prod

# Install staging to production
cp -r ~/stage ~/prod

# Restart production server
sudo systemctl start prod
