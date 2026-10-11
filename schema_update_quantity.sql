create extension if not exists "pgcrypto";

alter table list_items
add column if not exists quantity integer not null default 1;