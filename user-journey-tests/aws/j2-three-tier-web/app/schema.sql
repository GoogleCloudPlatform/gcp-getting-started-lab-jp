-- Online shop catalog — one table, unchanged since the 2016 build.
-- Single statement on purpose: db.bootstrap() runs this file as one execute.
CREATE TABLE IF NOT EXISTS books (
    id              INTEGER PRIMARY KEY,
    title           TEXT    NOT NULL,
    author          TEXT    NOT NULL,
    price_yen       INTEGER NOT NULL,
    published_year  INTEGER NOT NULL,
    condition_grade TEXT    NOT NULL,
    added_on        DATE    NOT NULL
);
