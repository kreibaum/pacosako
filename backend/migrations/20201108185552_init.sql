-- Add migration script here
CREATE TABLE `user` (
    `id` INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
    `username` TEXT NOT NULL UNIQUE,
    `password` TEXT
);

-- Defaul users: 'rolf' with password 'judita',
-- as well as 'doro' with password 'florian'.
INSERT INTO
    user (id, username, password)
VALUES
    (
        '1',
        'rolf',
        '$rpbkdf2$0$AAAnEA==$Wih697v+F5NJGvnRIldzLw==$Bqx2PYzgR5Dg+wBELKRsmt/HaV9LZXQ4QcYK70HNbsU=$'
    ),
    (
        '2',
        'doro',
        '$rpbkdf2$0$AAAnEA==$O/nqIkH/YIm/EzV8CfMIPA==$rN7hmPd3gmanCApEXQtsCd4SqA6+EKAu6HGqyvFJp50=$'
    );

CREATE TABLE `position` (
    `id` INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
    `owner` INTEGER NOT NULL,
    `data` TEXT
)