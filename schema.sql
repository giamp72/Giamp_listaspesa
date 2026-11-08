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

create table if not exists loyalty_cards (
  user_id uuid primary key references auth.users(id) on delete cascade,
  image_data text not null,
  updated_at timestamptz not null default now()
);

create table if not exists list_category_order (
  list_id uuid not null references shopping_lists(id) on delete cascade,
  category_id uuid not null references categories(id) on delete cascade,
  position integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (list_id, category_id)
);

create table if not exists list_templates (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  source_list_id uuid references shopping_lists(id) on delete set null,
  name text not null,
  recurrence text not null default 'none' check (recurrence in ('none', 'weekly', 'biweekly', 'monthly')),
  next_run_date date,
  created_at timestamptz not null default now()
);

create table if not exists list_template_items (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references list_templates(id) on delete cascade,
  position integer not null default 0,
  category_name text not null,
  description text not null,
  image_url text,
  quantity integer not null default 1,
  created_at timestamptz not null default now()
);

create table if not exists purchase_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  list_id uuid not null references shopping_lists(id) on delete cascade,
  product_id uuid references products(id) on delete set null,
  product_description text not null,
  category_name text,
  quantity integer not null default 1,
  purchased_at timestamptz not null default now()
);

create index if not exists idx_products_category_id on products(category_id);
create index if not exists idx_list_items_list_id on list_items(list_id);
create index if not exists idx_list_items_status on list_items(status);
create index if not exists idx_list_category_order_list_id on list_category_order(list_id);
create index if not exists idx_list_template_items_template_id on list_template_items(template_id);
create index if not exists idx_list_templates_owner_id on list_templates(owner_id);
create index if not exists idx_purchase_history_user_list_date on purchase_history(user_id, list_id, purchased_at desc);

alter table categories enable row level security;
alter table products enable row level security;
alter table shopping_lists enable row level security;
alter table list_items enable row level security;
alter table loyalty_cards enable row level security;
alter table list_category_order enable row level security;
alter table list_templates enable row level security;
alter table list_template_items enable row level security;
alter table purchase_history enable row level security;

drop policy if exists "auth all categories" on categories;
drop policy if exists "auth all products" on products;
drop policy if exists "auth all shopping_lists" on shopping_lists;
drop policy if exists "auth all list_items" on list_items;
drop policy if exists "users manage own loyalty card" on loyalty_cards;
drop policy if exists "auth all list_category_order" on list_category_order;
drop policy if exists "users manage own templates" on list_templates;
drop policy if exists "users manage own template items" on list_template_items;
drop policy if exists "users manage own purchase history" on purchase_history;

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

create policy "users manage own loyalty card"
on loyalty_cards
for all
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "auth all list_category_order"
on list_category_order
for all
to authenticated
using (true)
with check (true);

create policy "users manage own templates"
on list_templates
for all
to authenticated
using (auth.uid() = owner_id)
with check (auth.uid() = owner_id);

create policy "users manage own template items"
on list_template_items
for all
to authenticated
using (
  exists (
    select 1
    from list_templates t
    where t.id = list_template_items.template_id
      and t.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from list_templates t
    where t.id = list_template_items.template_id
      and t.owner_id = auth.uid()
  )
);

create policy "users manage own purchase history"
on purchase_history
for all
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

grant select, insert, update, delete on table loyalty_cards to authenticated;
grant select, insert, update, delete on table list_category_order to authenticated;
grant select, insert, update, delete on table list_templates to authenticated;
grant select, insert, update, delete on table list_template_items to authenticated;
grant select, insert, update, delete on table purchase_history to authenticated;

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