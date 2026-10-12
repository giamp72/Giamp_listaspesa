create table if not exists public.list_shares (
  list_id uuid not null references public.shopping_lists(id) on delete cascade,
  shared_with_id uuid not null references auth.users(id) on delete cascade,
  shared_with_email text not null,
  created_at timestamptz not null default now(),
  primary key (list_id, shared_with_id)
);

alter table public.shopping_lists enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.list_items enable row level security;
alter table public.list_shares enable row level security;

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

revoke all on function public.has_list_access(uuid) from public;
revoke all on function public.share_list_with_email(uuid, text) from public;
grant execute on function public.has_list_access(uuid) to authenticated;
grant execute on function public.share_list_with_email(uuid, text) to authenticated;

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

create policy "lists select accessible" on public.shopping_lists
for select to authenticated using (public.has_list_access(id));
create policy "lists insert owned" on public.shopping_lists
for insert to authenticated with check (owner_id = auth.uid());
create policy "lists update owned" on public.shopping_lists
for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "lists delete owned" on public.shopping_lists
for delete to authenticated using (owner_id = auth.uid());

drop policy if exists "categories list access" on public.categories;
create policy "categories list access" on public.categories
for all to authenticated
using (public.has_list_access(list_id))
with check (public.has_list_access(list_id));

drop policy if exists "products list access" on public.products;
create policy "products list access" on public.products
for all to authenticated
using (public.has_list_access(list_id))
with check (public.has_list_access(list_id));

drop policy if exists "list items list access" on public.list_items;
create policy "list items list access" on public.list_items
for all to authenticated
using (public.has_list_access(list_id))
with check (public.has_list_access(list_id));

drop policy if exists "shares select owned" on public.list_shares;
drop policy if exists "shares delete owned" on public.list_shares;
create policy "shares select owned" on public.list_shares
for select to authenticated
using (exists (select 1 from public.shopping_lists l where l.id = list_id and l.owner_id = auth.uid()));
create policy "shares delete owned" on public.list_shares
for delete to authenticated
using (exists (select 1 from public.shopping_lists l where l.id = list_id and l.owner_id = auth.uid()));
