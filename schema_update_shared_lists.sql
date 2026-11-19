do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'categories' and column_name = 'list_id'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'products' and column_name = 'list_id'
  ) then
    raise exception 'Le tabelle categories e products devono avere la colonna list_id.';
  end if;

  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise exception 'La publication supabase_realtime non esiste.';
  end if;
end
$$;

create table if not exists public.shopping_list_members (
  list_id uuid not null references public.shopping_lists(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  invited_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (list_id, user_id)
);

alter table public.shopping_lists enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.list_items enable row level security;
alter table public.list_category_order enable row level security;
alter table public.shopping_list_members enable row level security;

do $$
declare
  existing_policy record;
begin
  for existing_policy in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = any(array[
        'shopping_lists', 'categories', 'products', 'list_items',
        'list_category_order', 'shopping_list_members'
      ])
  loop
    execute format('drop policy %I on %I.%I',
      existing_policy.policyname, existing_policy.schemaname, existing_policy.tablename);
  end loop;
end
$$;

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

revoke all on function public.can_access_shopping_list(uuid) from public, anon;
grant execute on function public.can_access_shopping_list(uuid) to authenticated;

create policy "list members can view accessible lists"
on public.shopping_lists
for select
to authenticated
using (public.can_access_shopping_list(id));

create policy "owners create lists"
on public.shopping_lists
for insert
to authenticated
with check (owner_id = auth.uid());

create policy "owners update lists"
on public.shopping_lists
for update
to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

create policy "owners delete lists"
on public.shopping_lists
for delete
to authenticated
using (owner_id = auth.uid());

create policy "members view accessible categories"
on public.categories
for select
to authenticated
using (public.can_access_shopping_list(list_id));

create policy "owners manage categories"
on public.categories
for all
to authenticated
using (
  exists (
    select 1 from public.shopping_lists l
    where l.id = categories.list_id and l.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.shopping_lists l
    where l.id = categories.list_id and l.owner_id = auth.uid()
  )
);

create policy "members view accessible products"
on public.products
for select
to authenticated
using (public.can_access_shopping_list(list_id));

create policy "owners manage products"
on public.products
for all
to authenticated
using (
  exists (
    select 1 from public.shopping_lists l
    where l.id = products.list_id and l.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.shopping_lists l
    where l.id = products.list_id and l.owner_id = auth.uid()
  )
);

create policy "members manage items in accessible lists"
on public.list_items
for all
to authenticated
using (public.can_access_shopping_list(list_id))
with check (
  public.can_access_shopping_list(list_id)
  and exists (
    select 1
    from public.products p
    where p.id = list_items.product_id and p.list_id = list_items.list_id
  )
);

create policy "members view order in accessible lists"
on public.list_category_order
for select
to authenticated
using (public.can_access_shopping_list(list_id));

create policy "owners manage order in accessible lists"
on public.list_category_order
for all
to authenticated
using (
  exists (
    select 1 from public.shopping_lists l
    where l.id = list_category_order.list_id and l.owner_id = auth.uid()
  )
)
with check (
  public.can_access_shopping_list(list_id)
  and exists (
    select 1
    from public.categories c
    where c.id = list_category_order.category_id
      and c.list_id = list_category_order.list_id
  )
);

create policy "members view list membership"
on public.shopping_list_members
for select
to authenticated
using (public.can_access_shopping_list(list_id));

revoke all on public.shopping_list_members from public, anon, authenticated;
grant select on public.shopping_list_members to authenticated;

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

revoke all on function public.list_shopping_list_members(uuid) from public, anon;
revoke all on function public.share_shopping_list(uuid, text) from public, anon;
revoke all on function public.remove_shopping_list_member(uuid, uuid) from public, anon;
grant execute on function public.list_shopping_list_members(uuid) to authenticated;
grant execute on function public.share_shopping_list(uuid, text) to authenticated;
grant execute on function public.remove_shopping_list_member(uuid, uuid) to authenticated;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'categories', 'products', 'list_items', 'list_category_order',
    'shopping_lists', 'shopping_list_members'
  ]
  loop
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = table_name
    ) then
      execute format('alter publication supabase_realtime add table public.%I', table_name);
    end if;
  end loop;
end
$$;
