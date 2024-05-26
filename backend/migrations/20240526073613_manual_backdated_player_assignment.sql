-- I want people who are not me to update player assignments on games where they
-- didn't log in properly. This allows them to take over that task and I no longer
-- have to do that. This means I need some additions to the database:
--
-- Audit log: Who changed which game, when?
-- Permissions: Who is allowed to change games at all?
--
-- For the permissions I'm not going for full roll based access control (RBAC)
-- but assign permissions directly to users. I'm also not maintaining a table of
-- all permissions in the database, I just assign string permissions to users.

-- Add the user permission table:
CREATE TABLE user_permission (
    user_id INTEGER NOT NULL,
    permission TEXT NOT NULL,
    PRIMARY KEY (user_id, permission),
    FOREIGN KEY (user_id) REFERENCES user(id)
);

-- Add the audit log table:
CREATE TABLE game_assignment_audit (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    game_id INTEGER NOT NULL,
    assigned_by INTEGER NOT NULL,
    assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    white_assignee INTEGER,
    black_assignee INTEGER,
    FOREIGN KEY (game_id) REFERENCES game(id),
    FOREIGN KEY (assigned_by) REFERENCES user(id)
    FOREIGN KEY (white_assignee) REFERENCES user(id)
    FOREIGN KEY (black_assignee) REFERENCES user(id)
);