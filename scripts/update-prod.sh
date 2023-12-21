# Takes the staging server and replaces the production server.

# Makes a backup of the prod server database.
# No need to back up any assets, everything is in version control anyway.
./create-backup.sh

# Start timer
start_time=$(date +%s%3N)

# Shut down production server
sudo systemctl stop prod

# Remove existing deployment
rm -rf ~/prod

# Install staging to production
cp -r ~/stage ~/prod

# Restart production server
sudo systemctl start prod

# Stop timer
end_time=$(date +%s%3N)
duration=$((end_time - start_time))

# Append a line to /home/pacosako/log/prod-restart-log.txt
mkdir -p /home/pacosako/log/
echo "UPDATE: Restart on $(date +'%Y-%m-%d %H:%M') took ${duration} milliseconds" >> /home/pacosako/log/prod-restart-log.md
