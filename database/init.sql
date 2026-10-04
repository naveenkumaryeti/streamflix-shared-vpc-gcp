CREATE TABLE IF NOT EXISTS movies (
  id SERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  genre TEXT NOT NULL,
  year INT NOT NULL
);
INSERT INTO movies (title, genre, year) VALUES
  ('Space Odyssey',   'Sci-Fi',  2021),
  ('Laugh Riot',      'Comedy',  2020),
  ('Midnight Heist',  'Thriller',2022),
  ('Monsoon Memories','Drama',   2023);
