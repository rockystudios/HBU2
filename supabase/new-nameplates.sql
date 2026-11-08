-- Run after coins.sql to add these plates to an existing setup. Safe to run again.
insert into public.plates (id, name, price, name_color, bg, sort) values
  ('arctic',    'Arctic Ice',   175, '#bff5ff', 'linear-gradient(105deg, rgba(32,115,180,.55), rgba(135,230,255,.3))', 8),
  ('sunset',    'Sunset',       250, '#ffd0a3', 'linear-gradient(105deg, rgba(245,90,70,.5), rgba(234,124,39,.32))', 9),
  ('forest',    'Enchanted Forest', 350, '#b4ffbd', 'linear-gradient(105deg, rgba(15,100,65,.6), rgba(55,160,92,.32))', 10),
  ('lavender',  'Lavender Dream', 400, '#f0d7ff', 'linear-gradient(105deg, rgba(127,72,194,.58), rgba(220,133,235,.3))', 11),
  ('storm',     'Thunderstorm', 450, '#d7eaff', 'linear-gradient(105deg, rgba(38,51,96,.7), rgba(88,112,150,.4))', 12),
  ('cherry',    'Cherry Blossom', 550, '#ffd7ec', 'linear-gradient(105deg, rgba(198,53,112,.55), rgba(255,161,205,.3))', 13),
  ('aurora',    'Aurora',       650, '#c6ffe9', 'linear-gradient(105deg, rgba(29,147,148,.55), rgba(105,71,196,.48), rgba(50,185,122,.35))', 14),
  ('inferno',   'Inferno',      800, '#ffe1a3', 'linear-gradient(105deg, rgba(155,35,29,.7), rgba(255,125,23,.4))', 15),
  ('cosmic',    'Cosmic Nebula', 900, '#e8d0ff', 'linear-gradient(105deg, rgba(40,25,105,.72), rgba(163,49,164,.48), rgba(45,99,184,.45))', 16),
  ('diamond',   'Diamond',     1200, '#e9fcff', 'linear-gradient(105deg, rgba(31,127,164,.65), rgba(169,236,255,.38), rgba(87,130,208,.48))', 17)
on conflict (id) do nothing;
