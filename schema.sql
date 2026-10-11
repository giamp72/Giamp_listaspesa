create extension if not exists "pgcrypto";

create table if not exists categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  position integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists products (
  id uuid primary key default gen_random_uuid(),
  description text not null,
  category_id uuid not null references categories(id) on delete restrict,
  image_url text,
  created_at timestamptz not null default now()
);

create table if not exists shopping_lists (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists list_items (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references shopping_lists(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  status text not null default 'to_buy' check (status in ('to_buy', 'purchased')),
  updated_at timestamptz not null default now(),
  unique (list_id, product_id)
);

create index if not exists idx_products_category_id on products(category_id);
create index if not exists idx_list_items_list_id on list_items(list_id);
create index if not exists idx_list_items_status on list_items(status);

alter table categories enable row level security;
alter table products enable row level security;
alter table shopping_lists enable row level security;
alter table list_items enable row level security;

drop policy if exists "auth all categories" on categories;
drop policy if exists "auth all products" on products;
drop policy if exists "auth all shopping_lists" on shopping_lists;
drop policy if exists "auth all list_items" on list_items;

create policy "auth all categories"
on categories
for all
to authenticated
using (true)
with check (true);

create policy "auth all products"
on products
for all
to authenticated
using (true)
with check (true);

create policy "auth all shopping_lists"
on shopping_lists
for all
to authenticated
using (true)
with check (true);

create policy "auth all list_items"
on list_items
for all
to authenticated
using (true)
with check (true);

insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do nothing;

drop policy if exists "img read" on storage.objects;
drop policy if exists "img insert" on storage.objects;
drop policy if exists "img delete" on storage.objects;

create policy "img read"
on storage.objects
for select
using (bucket_id = 'product-images');

create policy "img insert"
on storage.objects
for insert
to authenticated
with check (bucket_id = 'product-images');

create policy "img delete"
on storage.objects
for delete
to authenticated
using (bucket_id = 'product-images');