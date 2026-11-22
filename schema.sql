-- Schema completo di Giamp_listaspesa, allineato al database in produzione (novembre 2026).
-- Per una nuova installazione: esegui questo file una sola volta nel SQL Editor di Supabase.
-- Per aggiornare un database esistente usa invece i file nella cartella migrations/.
--
-- Nessuna policy usa "using (true)": ogni utente vede solo le liste di cui è
-- proprietario o a cui è stato invitato (can_access_shopping_list).

create extension if not exists pgcrypto;

-- ---------- Tabelle ----------

create table if not exists public.shopping_lists (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.shopping_list_members (
  list_id uuid not null references public.shopping_lists(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  invited_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (list_id, user_id)
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references public.shopping_lists(id) on delete cascade,
  name text not null,
  position integer not null default 0,
  created_at timestamptz not null default now()
);
create unique index if not exists categories_list_name_uq on public.categories (list_id, name);
create index if not exists idx_categories_list on public.categories (list_id);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references public.shopping_lists(id) on delete cascade,
  category_id uuid not null references public.categories(id) on delete restrict,
  description text not null,
  image_url text,
  created_at timestamptz not null default now()
);
create index if not exists idx_products_list on public.products (list_id);
create index if not exists idx_products_category_id on public.products (category_id);

create table if not exists public.list_items (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references public.shopping_lists(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  quantity integer not null default 1,
  status text not null default 'to_buy' check (status in ('to_buy', 'purchased')),
  updated_at timestamptz not null default now(),
  unique (list_id, product_id)
);
create index if not exists idx_list_items_list_id on public.list_items (list_id);
create index if not exists idx_list_items_status on public.list_items (status);

create table if not exists public.list_category_order (
  list_id uuid not null references public.shopping_lists(id) on delete cascade,
  category_id uuid not null references public.categories(id) on delete cascade,
  position integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (list_id, category_id)
);
create index if not exists idx_list_category_order_list_id on public.list_category_order (list_id);

create table if not exists public.purchase_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  list_id uuid not null references public.shopping_lists(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_description text not null,
  category_name text,
  quantity integer not null default 1,
  purchased_at timestamptz not null default now()
);
create index if not exists idx_purchase_history_user_list_date
  on public.purchase_history (user_id, list_id, purchased_at desc);

create table if not exists public.loyalty_cards (
  user_id uuid primary key references auth.users(id) on delete cascade,
  image_data text not null,
  updated_at timestamptz not null default now()
);

-- Modelli di lista: presenti nel database ma non ancora usati dall'interfaccia.
create table if not exists public.list_templates (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  source_list_id uuid references public.shopping_lists(id) on delete set null,
  recurrence text not null default 'none' check (recurrence in ('none', 'weekly', 'biweekly', 'monthly')),
  next_run_date date,
  created_at timestamptz not null default now()
);
create index if not exists idx_list_templates_owner_id on public.list_templates (owner_id);

create table if not exists public.list_template_items (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.list_templates(id) on delete cascade,
  category_name text not null,
  description text not null,
  image_url text,
  quantity integer not null default 1,
  position integer not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists idx_list_template_items_template_id on public.list_template_items (template_id);

-- ---------- Funzioni ----------

create or replace function public.can_access_shopping_list(p_list_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.shopping_lists l
    where l.id = p_list_id
      and (
        l.owner_id = auth.uid()
        or exists (
          select 1
          from public.shopping_list_members m
          where m.list_id = l.id and m.user_id = auth.uid()
        )
      )
  );
$$;

create or replace function public.list_shopping_list_members(p_list_id uuid)
returns table(user_id uuid, email text, is_owner boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select u.id, u.email::text, u.id = l.owner_id
  from public.shopping_lists l
  join auth.users u on u.id = l.owner_id
  where l.id = p_list_id
    and public.can_access_shopping_list(p_list_id)
  union all
  select u.id, u.email::text, false
  from public.shopping_list_members m
  join auth.users u on u.id = m.user_id
  where m.list_id = p_list_id
    and public.can_access_shopping_list(p_list_id);
$$;

create or replace function public.share_shopping_list(p_list_id uuid, p_email text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  target_id uuid;
begin
  if actor_id is null then
    raise exception 'Devi accedere per condividere una lista.';
  end if;

  if not exists (
    select 1 from public.shopping_lists
    where id = p_list_id and owner_id = actor_id
  ) then
    raise exception 'Solo il proprietario può invitare utenti.';
  end if;

  select id into target_id
  from auth.users
  where lower(email) = lower(trim(p_email));

  if target_id is null then
    raise exception 'Nessun utente registrato trovato con questa email.';
  end if;

  if target_id = actor_id then
    raise exception 'Non puoi invitare il tuo stesso account.';
  end if;

  insert into public.shopping_list_members(list_id, user_id, invited_by)
  values (p_list_id, target_id, actor_id)
  on conflict (list_id, user_id) do nothing;
end;
$$;

create or replace function public.remove_shopping_list_member(p_list_id uuid, p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.shopping_lists
    where id = p_list_id and owner_id = auth.uid()
  ) then
    raise exception 'Solo il proprietario può rimuovere utenti.';
  end if;

  delete from public.shopping_list_members
  where list_id = p_list_id and user_id = p_member_id;
end;
$$;

-- Chiusura carrello atomica: storico e rimozione degli acquistati nella stessa istruzione.
create or replace function public.close_shopping_cart(p_list_id uuid)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  saved integer;
begin
  if uid is null then
    raise exception 'Devi accedere per chiudere il carrello.';
  end if;
  if not public.can_access_shopping_list(p_list_id) then
    raise exception 'Lista non trovata o non accessibile.';
  end if;

  with removed as (
    delete from public.list_items i
    where i.list_id = p_list_id and i.status = 'purchased'
    returning i.product_id, i.quantity
  ), inserted as (
    insert into public.purchase_history
      (user_id, list_id, product_id, product_description, category_name, quantity, purchased_at)
    select uid, p_list_id, r.product_id, p.description, c.name, r.quantity, now()
    from removed r
    join public.products p on p.id = r.product_id
    left join public.categories c on c.id = p.category_id
    returning 1
  )
  select count(*) into saved from inserted;

  return saved;
end;
$$;

-- Import JSON atomico: se qualcosa fallisce la lista resta com'era. Solo il proprietario.
create or replace function public.import_shopping_list(p_list_id uuid, p_data jsonb)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  cat_raw text;
  cat_name text;
  cat_pos bigint;
  cat_id uuid;
  item jsonb;
  descr text;
  img text;
begin
  if auth.uid() is null or not exists (
    select 1 from public.shopping_lists where id = p_list_id and owner_id = auth.uid()
  ) then
    raise exception 'Solo il proprietario può importare in questa lista.';
  end if;
  if jsonb_typeof(p_data -> 'categorie') is distinct from 'array'
     or jsonb_typeof(p_data -> 'prodotti') is distinct from 'object' then
    raise exception 'Formato JSON non valido.';
  end if;

  delete from public.list_items where list_id = p_list_id;
  delete from public.products where list_id = p_list_id;
  delete from public.categories where list_id = p_list_id;

  for cat_raw, cat_name, cat_pos in
    select value #>> '{}', trim(value #>> '{}'), ordinality - 1
    from jsonb_array_elements(p_data -> 'categorie') with ordinality
  loop
    if coalesce(cat_name, '') = '' then
      raise exception 'Categoria senza nome nel file.';
    end if;

    insert into public.categories (list_id, name, position)
    values (p_list_id, cat_name, cat_pos)
    returning id into cat_id;

    insert into public.list_category_order (list_id, category_id, position)
    values (p_list_id, cat_id, cat_pos);

    if jsonb_typeof(p_data -> 'prodotti' -> cat_raw) = 'array' then
      for item in select value from jsonb_array_elements(p_data -> 'prodotti' -> cat_raw)
      loop
        if jsonb_typeof(item) = 'string' then
          descr := trim(item #>> '{}');
          img := null;
        elsif jsonb_typeof(item) = 'object' then
          descr := trim(item ->> 'descrizione');
          img := item ->> 'immagine';
        else
          continue;
        end if;
        if coalesce(descr, '') = '' then
          continue;
        end if;
        if img !~ '^https://[a-z0-9]+\.supabase\.co/storage/v1/object/public/product-images/[A-Za-z0-9._%-]+$' then
          img := null;
        end if;
        insert into public.products (list_id, category_id, description, image_url)
        values (p_list_id, cat_id, descr, img);
      end loop;
    end if;
  end loop;
end;
$$;

revoke all on function public.can_access_shopping_list(uuid) from public, anon;
revoke all on function public.list_shopping_list_members(uuid) from public, anon;
revoke all on function public.share_shopping_list(uuid, text) from public, anon;
revoke all on function public.remove_shopping_list_member(uuid, uuid) from public, anon;
revoke all on function public.close_shopping_cart(uuid) from public, anon;
revoke all on function public.import_shopping_list(uuid, jsonb) from public, anon;
grant execute on function public.can_access_shopping_list(uuid) to authenticated;
grant execute on function public.list_shopping_list_members(uuid) to authenticated;
grant execute on function public.share_shopping_list(uuid, text) to authenticated;
grant execute on function public.remove_shopping_list_member(uuid, uuid) to authenticated;
grant execute on function public.close_shopping_cart(uuid) to authenticated;
grant execute on function public.import_shopping_list(uuid, jsonb) to authenticated;

-- ---------- Row Level Security ----------

alter table public.shopping_lists enable row level security;
alter table public.shopping_list_members enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.list_items enable row level security;
alter table public.list_category_order enable row level security;
alter table public.purchase_history enable row level security;
alter table public.loyalty_cards enable row level security;
alter table public.list_templates enable row level security;
alter table public.list_template_items enable row level security;

drop policy if exists "list members can view accessible lists" on public.shopping_lists;
create policy "list members can view accessible lists" on public.shopping_lists
  for select to authenticated using (public.can_access_shopping_list(id));
drop policy if exists "owners create lists" on public.shopping_lists;
create policy "owners create lists" on public.shopping_lists
  for insert to authenticated with check (owner_id = auth.uid());
drop policy if exists "owners update lists" on public.shopping_lists;
create policy "owners update lists" on public.shopping_lists
  for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop policy if exists "owners delete lists" on public.shopping_lists;
create policy "owners delete lists" on public.shopping_lists
  for delete to authenticated using (owner_id = auth.uid());

drop policy if exists "members view list membership" on public.shopping_list_members;
create policy "members view list membership" on public.shopping_list_members
  for select to authenticated using (public.can_access_shopping_list(list_id));

drop policy if exists "members manage accessible categories" on public.categories;
create policy "members manage accessible categories" on public.categories
  for all to authenticated
  using (public.can_access_shopping_list(list_id))
  with check (public.can_access_shopping_list(list_id));

drop policy if exists "members manage accessible products" on public.products;
create policy "members manage accessible products" on public.products
  for all to authenticated
  using (public.can_access_shopping_list(list_id))
  with check (
    public.can_access_shopping_list(list_id)
    and exists (
      select 1 from public.shopping_lists l
      join public.categories c on c.id = products.category_id
      where l.id = products.list_id and c.list_id = products.list_id
    )
  );

drop policy if exists "members manage items in accessible lists" on public.list_items;
create policy "members manage items in accessible lists" on public.list_items
  for all to authenticated
  using (public.can_access_shopping_list(list_id))
  with check (
    public.can_access_shopping_list(list_id)
    and exists (
      select 1 from public.products p
      where p.id = list_items.product_id and p.list_id = list_items.list_id
    )
  );

drop policy if exists "members manage order in accessible lists" on public.list_category_order;
create policy "members manage order in accessible lists" on public.list_category_order
  for all to authenticated
  using (public.can_access_shopping_list(list_id))
  with check (
    public.can_access_shopping_list(list_id)
    and exists (
      select 1 from public.categories c
      where c.id = list_category_order.category_id and c.list_id = list_category_order.list_id
    )
  );

drop policy if exists "users manage own purchase history" on public.purchase_history;
create policy "users manage own purchase history" on public.purchase_history
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "users manage own loyalty card" on public.loyalty_cards;
create policy "users manage own loyalty card" on public.loyalty_cards
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "users manage own templates" on public.list_templates;
create policy "users manage own templates" on public.list_templates
  for all to authenticated using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

drop policy if exists "users manage own template items" on public.list_template_items;
create policy "users manage own template items" on public.list_template_items
  for all to authenticated
  using (exists (select 1 from public.list_templates t where t.id = list_template_items.template_id and t.owner_id = auth.uid()))
  with check (exists (select 1 from public.list_templates t where t.id = list_template_items.template_id and t.owner_id = auth.uid()));

-- ---------- Aggiornamenti in tempo reale ----------

do $$
declare
  t text;
begin
  foreach t in array array['shopping_lists','shopping_list_members','categories','products','list_items','list_category_order']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end;
$$;

-- ---------- Foto prodotto ----------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('product-images', 'product-images', true, 10485760,
        array['image/jpeg','image/png','image/webp','image/gif','image/heic','image/heif'])
on conflict (id) do update
set file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "img read" on storage.objects;
create policy "img read" on storage.objects
  for select to public using (bucket_id = 'product-images');
drop policy if exists "img insert" on storage.objects;
create policy "img insert" on storage.objects
  for insert to authenticated with check (bucket_id = 'product-images');
drop policy if exists "img delete" on storage.objects;
drop policy if exists "img delete own" on storage.objects;
create policy "img delete own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'product-images' and owner_id = (select auth.uid())::text);
