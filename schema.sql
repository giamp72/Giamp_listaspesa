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

create table if not exists list_shares (
  list_id uuid not null references shopping_lists(id) on delete cascade,
  shared_with_id uuid not null references auth.users(id) on delete cascade,
  shared_with_email text not null,
  created_at timestamptz not null default now(),
  primary key (list_id, shared_with_id)
);

create index if not exists idx_products_category_id on products(category_id);
create index if not exists idx_list_items_list_id on list_items(list_id);
create index if not exists idx_list_items_status on list_items(status);

alter table categories enable row level security;
alter table products enable row level security;
alter table shopping_lists enable row level security;
alter table list_items enable row level security;
alter table list_shares enable row level security;

do $$
declare
  existing_policy record;
begin
  for existing_policy in
    select tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('shopping_lists', 'categories', 'products', 'list_items', 'list_shares')
  loop
    execute format(
      'drop policy if exists %I on public.%I',
      existing_policy.policyname,
      existing_policy.tablename
    );
  end loop;
end;
$$;

create or replace function public.has_list_access(p_list_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.shopping_lists l
    where l.id = p_list_id and l.owner_id = auth.uid()
  ) or exists (
    select 1
    from public.list_shares s
    where s.list_id = p_list_id and s.shared_with_id = auth.uid()
  );
$$;

create or replace function public.share_list_with_email(p_list_id uuid, p_email text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  recipient_id uuid;
  normalized_email text := lower(trim(p_email));
begin
  if not exists (
    select 1 from public.shopping_lists
    where id = p_list_id and owner_id = auth.uid()
  ) then
    raise exception 'Solo il proprietario può condividere questa lista.';
  end if;

  if normalized_email is null or normalized_email = '' then
    raise exception 'Inserisci un indirizzo email valido.';
  end if;

  select id into recipient_id
  from auth.users
  where lower(email) = normalized_email;

  if recipient_id is null then
    raise exception 'Nessun utente registrato con questa email.';
  end if;

  if recipient_id = auth.uid() then
    raise exception 'Non puoi condividere la lista con te stesso.';
  end if;

  insert into public.list_shares (list_id, shared_with_id, shared_with_email)
  values (p_list_id, recipient_id, normalized_email)
  on conflict (list_id, shared_with_id)
  do update set shared_with_email = excluded.shared_with_email;
end;
$$;

create or replace function public.create_shopping_list(p_name text)
returns setof public.shopping_lists
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'Devi accedere per creare una lista.';
  end if;

  if nullif(trim(p_name), '') is null then
    raise exception 'Il nome della lista è obbligatorio.';
  end if;

  return query
  insert into public.shopping_lists (name, owner_id)
  values (trim(p_name), auth.uid())
  returning *;
end;
$$;

revoke all on function public.has_list_access(uuid) from public;
revoke all on function public.share_list_with_email(uuid, text) from public;
revoke all on function public.create_shopping_list(text) from public;
grant execute on function public.has_list_access(uuid) to authenticated;
grant execute on function public.share_list_with_email(uuid, text) to authenticated;
grant execute on function public.create_shopping_list(text) to authenticated;

drop policy if exists "lists select accessible" on shopping_lists;
drop policy if exists "lists insert owned" on shopping_lists;
drop policy if exists "lists update owned" on shopping_lists;
drop policy if exists "lists delete owned" on shopping_lists;
create policy "lists select accessible" on shopping_lists
for select to authenticated using (public.has_list_access(id));
create policy "lists insert owned" on shopping_lists
for insert to authenticated with check (owner_id = auth.uid());
create policy "lists update owned" on shopping_lists
for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "lists delete owned" on shopping_lists
for delete to authenticated using (owner_id = auth.uid());

drop policy if exists "categories list access" on categories;
create policy "categories list access" on categories
for all to authenticated
using (public.has_list_access(list_id))
with check (public.has_list_access(list_id));

drop policy if exists "products list access" on products;
create policy "products list access" on products
for all to authenticated
using (public.has_list_access(list_id))
with check (public.has_list_access(list_id));

drop policy if exists "list items list access" on list_items;
create policy "list items list access" on list_items
for all to authenticated
using (public.has_list_access(list_id))
with check (public.has_list_access(list_id));

drop policy if exists "shares select owned" on list_shares;
drop policy if exists "shares delete owned" on list_shares;
create policy "shares select owned" on list_shares
for select to authenticated
using (exists (select 1 from public.shopping_lists l where l.id = list_id and l.owner_id = auth.uid()));
create policy "shares delete owned" on list_shares
for delete to authenticated
using (exists (select 1 from public.shopping_lists l where l.id = list_id and l.owner_id = auth.uid()));

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