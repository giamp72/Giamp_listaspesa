create extension if not exists "pgcrypto";

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

create index if not exists idx_list_category_order_list_id on list_category_order(list_id);
create index if not exists idx_list_templates_owner_id on list_templates(owner_id);
create index if not exists idx_list_template_items_template_id on list_template_items(template_id);
create index if not exists idx_purchase_history_user_list_date on purchase_history(user_id, list_id, purchased_at desc);

alter table list_category_order enable row level security;
alter table list_templates enable row level security;
alter table list_template_items enable row level security;
alter table purchase_history enable row level security;

drop policy if exists "auth all list_category_order" on list_category_order;
drop policy if exists "users manage own templates" on list_templates;
drop policy if exists "users manage own template items" on list_template_items;
drop policy if exists "users manage own purchase history" on purchase_history;

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

grant select, insert, update, delete on table list_category_order to authenticated;
grant select, insert, update, delete on table list_templates to authenticated;
grant select, insert, update, delete on table list_template_items to authenticated;
grant select, insert, update, delete on table purchase_history to authenticated;
