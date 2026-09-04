-- =============================================================================
-- Chinook Database Schema for PostgreSQL
-- =============================================================================
-- Based on the Chinook Database v1.4.5 by Luis Rocha
-- https://github.com/lerocha/chinook-database
--
-- Adapted to use snake_case naming for Debezium CDC / BigQuery compatibility.
-- Uses IF NOT EXISTS for idempotent re-runs.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Lookup / Reference Tables
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS genre (
    genre_id INT NOT NULL,
    name VARCHAR(120),
    CONSTRAINT pk_genre PRIMARY KEY (genre_id)
);

CREATE TABLE IF NOT EXISTS media_type (
    media_type_id INT NOT NULL,
    name VARCHAR(120),
    CONSTRAINT pk_media_type PRIMARY KEY (media_type_id)
);

-- -----------------------------------------------------------------------------
-- Artist / Album / Track
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS artist (
    artist_id INT NOT NULL,
    name VARCHAR(120),
    CONSTRAINT pk_artist PRIMARY KEY (artist_id)
);

CREATE TABLE IF NOT EXISTS album (
    album_id INT NOT NULL,
    title VARCHAR(160) NOT NULL,
    artist_id INT NOT NULL,
    CONSTRAINT pk_album PRIMARY KEY (album_id)
);

CREATE TABLE IF NOT EXISTS track (
    track_id INT NOT NULL,
    name VARCHAR(200) NOT NULL,
    album_id INT,
    media_type_id INT NOT NULL,
    genre_id INT,
    composer VARCHAR(220),
    milliseconds INT NOT NULL,
    bytes INT,
    unit_price NUMERIC(10,2) NOT NULL,
    CONSTRAINT pk_track PRIMARY KEY (track_id)
);

-- -----------------------------------------------------------------------------
-- Employee / Customer
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS employee (
    employee_id INT NOT NULL,
    last_name VARCHAR(20) NOT NULL,
    first_name VARCHAR(20) NOT NULL,
    title VARCHAR(30),
    reports_to INT,
    birth_date TIMESTAMP,
    hire_date TIMESTAMP,
    address VARCHAR(70),
    city VARCHAR(40),
    state VARCHAR(40),
    country VARCHAR(40),
    postal_code VARCHAR(10),
    phone VARCHAR(24),
    fax VARCHAR(24),
    email VARCHAR(60),
    CONSTRAINT pk_employee PRIMARY KEY (employee_id)
);

CREATE TABLE IF NOT EXISTS customer (
    customer_id INT NOT NULL,
    first_name VARCHAR(40) NOT NULL,
    last_name VARCHAR(20) NOT NULL,
    company VARCHAR(80),
    address VARCHAR(70),
    city VARCHAR(40),
    state VARCHAR(40),
    country VARCHAR(40),
    postal_code VARCHAR(10),
    phone VARCHAR(24),
    fax VARCHAR(24),
    email VARCHAR(60) NOT NULL,
    support_rep_id INT,
    CONSTRAINT pk_customer PRIMARY KEY (customer_id)
);

-- -----------------------------------------------------------------------------
-- Invoice / Invoice Line
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS invoice (
    invoice_id INT NOT NULL,
    customer_id INT NOT NULL,
    invoice_date TIMESTAMP NOT NULL,
    billing_address VARCHAR(70),
    billing_city VARCHAR(40),
    billing_state VARCHAR(40),
    billing_country VARCHAR(40),
    billing_postal_code VARCHAR(10),
    total NUMERIC(10,2) NOT NULL,
    CONSTRAINT pk_invoice PRIMARY KEY (invoice_id)
);

CREATE TABLE IF NOT EXISTS invoice_line (
    invoice_line_id INT NOT NULL,
    invoice_id INT NOT NULL,
    track_id INT NOT NULL,
    unit_price NUMERIC(10,2) NOT NULL,
    quantity INT NOT NULL,
    CONSTRAINT pk_invoice_line PRIMARY KEY (invoice_line_id)
);

-- -----------------------------------------------------------------------------
-- Playlist / Playlist Track
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS playlist (
    playlist_id INT NOT NULL,
    name VARCHAR(120),
    CONSTRAINT pk_playlist PRIMARY KEY (playlist_id)
);

CREATE TABLE IF NOT EXISTS playlist_track (
    playlist_id INT NOT NULL,
    track_id INT NOT NULL,
    CONSTRAINT pk_playlist_track PRIMARY KEY (playlist_id, track_id)
);

-- =============================================================================
-- Foreign Keys
-- =============================================================================

ALTER TABLE album DROP CONSTRAINT IF EXISTS fk_album_artist_id;
ALTER TABLE album ADD CONSTRAINT fk_album_artist_id
    FOREIGN KEY (artist_id) REFERENCES artist (artist_id) ON DELETE NO ACTION ON UPDATE NO ACTION;

ALTER TABLE track DROP CONSTRAINT IF EXISTS fk_track_album_id;
ALTER TABLE track ADD CONSTRAINT fk_track_album_id
    FOREIGN KEY (album_id) REFERENCES album (album_id) ON DELETE NO ACTION ON UPDATE NO ACTION;

ALTER TABLE track DROP CONSTRAINT IF EXISTS fk_track_genre_id;
ALTER TABLE track ADD CONSTRAINT fk_track_genre_id
    FOREIGN KEY (genre_id) REFERENCES genre (genre_id) ON DELETE NO ACTION ON UPDATE NO ACTION;

ALTER TABLE track DROP CONSTRAINT IF EXISTS fk_track_media_type_id;
ALTER TABLE track ADD CONSTRAINT fk_track_media_type_id
    FOREIGN KEY (media_type_id) REFERENCES media_type (media_type_id) ON DELETE NO ACTION ON UPDATE NO ACTION;

ALTER TABLE employee DROP CONSTRAINT IF EXISTS fk_employee_reports_to;
ALTER TABLE employee ADD CONSTRAINT fk_employee_reports_to
    FOREIGN KEY (reports_to) REFERENCES employee (employee_id) ON DELETE NO ACTION ON UPDATE NO ACTION;

ALTER TABLE customer DROP CONSTRAINT IF EXISTS fk_customer_support_rep_id;
ALTER TABLE customer ADD CONSTRAINT fk_customer_support_rep_id
    FOREIGN KEY (support_rep_id) REFERENCES employee (employee_id) ON DELETE NO ACTION ON UPDATE NO ACTION;

ALTER TABLE invoice DROP CONSTRAINT IF EXISTS fk_invoice_customer_id;
ALTER TABLE invoice ADD CONSTRAINT fk_invoice_customer_id
    FOREIGN KEY (customer_id) REFERENCES customer (customer_id) ON DELETE NO ACTION ON UPDATE NO ACTION;

ALTER TABLE invoice_line DROP CONSTRAINT IF EXISTS fk_invoice_line_invoice_id;
ALTER TABLE invoice_line ADD CONSTRAINT fk_invoice_line_invoice_id
    FOREIGN KEY (invoice_id) REFERENCES invoice (invoice_id) ON DELETE NO ACTION ON UPDATE NO ACTION;

ALTER TABLE invoice_line DROP CONSTRAINT IF EXISTS fk_invoice_line_track_id;
ALTER TABLE invoice_line ADD CONSTRAINT fk_invoice_line_track_id
    FOREIGN KEY (track_id) REFERENCES track (track_id) ON DELETE NO ACTION ON UPDATE NO ACTION;

ALTER TABLE playlist_track DROP CONSTRAINT IF EXISTS fk_playlist_track_playlist_id;
ALTER TABLE playlist_track ADD CONSTRAINT fk_playlist_track_playlist_id
    FOREIGN KEY (playlist_id) REFERENCES playlist (playlist_id) ON DELETE NO ACTION ON UPDATE NO ACTION;

ALTER TABLE playlist_track DROP CONSTRAINT IF EXISTS fk_playlist_track_track_id;
ALTER TABLE playlist_track ADD CONSTRAINT fk_playlist_track_track_id
    FOREIGN KEY (track_id) REFERENCES track (track_id) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- =============================================================================
-- Foreign Key Indexes
-- =============================================================================

CREATE INDEX IF NOT EXISTS ifk_album_artist_id ON album (artist_id);
CREATE INDEX IF NOT EXISTS ifk_track_album_id ON track (album_id);
CREATE INDEX IF NOT EXISTS ifk_track_genre_id ON track (genre_id);
CREATE INDEX IF NOT EXISTS ifk_track_media_type_id ON track (media_type_id);
CREATE INDEX IF NOT EXISTS ifk_employee_reports_to ON employee (reports_to);
CREATE INDEX IF NOT EXISTS ifk_customer_support_rep_id ON customer (support_rep_id);
CREATE INDEX IF NOT EXISTS ifk_invoice_customer_id ON invoice (customer_id);
CREATE INDEX IF NOT EXISTS ifk_invoice_line_invoice_id ON invoice_line (invoice_id);
CREATE INDEX IF NOT EXISTS ifk_invoice_line_track_id ON invoice_line (track_id);
CREATE INDEX IF NOT EXISTS ifk_playlist_track_playlist_id ON playlist_track (playlist_id);
CREATE INDEX IF NOT EXISTS ifk_playlist_track_track_id ON playlist_track (track_id);
