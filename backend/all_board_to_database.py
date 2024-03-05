import sqlite3
import csv

# Connect to SQLite database (this will create the database if it doesn't exist)
conn = sqlite3.connect('all_boards.sqlite')
cur = conn.cursor()

# Create table with the new structure
cur.execute('''
CREATE TABLE IF NOT EXISTS games (
    game_id INTEGER,
    half_move_count INTEGER,
    victory_state TEXT,
    fen TEXT
)
''')

# Open the CSV file and insert its data into the table
with open('all_boards.csv', 'r') as csv_file:
    # Use DictReader to easily access data by column names
    csv_reader = csv.DictReader(csv_file)
    for row in csv_reader:
        # Insert data into the table
        cur.execute('''INSERT INTO games (game_id, half_move_count, victory_state, fen)
                    VALUES (?, ?, ?, ?)''', 
                    (row['game_id'], row['half_move_count'], row['victory_state'], row['fen']))

# Commit changes and close the connection
conn.commit()
conn.close()
