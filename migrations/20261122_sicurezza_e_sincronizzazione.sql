-- Migrazione 2026-11-22: sicurezza e sincronizzazione
-- Da eseguire una volta sul database esistente, PRIMA di pubblicare il nuovo index.html.
-- È rieseguibile senza effetti collaterali.

-- 1. Foto prodotto: ognuno può cancellare solo i file che ha caricato,
--    e il bucket accetta solo immagini fino a 10 MB.
drop policy if exists "img delete" on storage.objects;
drop policy if exists "img delete own" on storage.objects;
create policy "img delete own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'product-images' and owner_id = (select auth.uid())::text);

update storage.buckets
set file_size_limit = 10485760,
    allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif','image/heic','image/heif']
where id = 'product-images';

-- 2. Chiusura carrello atomica: lo storico viene scritto e gli articoli acquistati
--    rimossi nella stessa istruzione. Una seconda chiamata non trova più nulla,
--    quindi lo storico non può essere registrato due volte.
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

-- 3. Import JSON atomico: se qualcosa fallisce la lista resta com'era.
--    Solo il proprietario può importare. Accetta solo immagini del bucket del progetto.
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
  delete from public.categories where list_id = p_list_id;  -- list_category_order va in cascata

  for cat_raw, cat_name, cat_pos in
    select value #>> '{}', trim(value #>> '{}'), ordinality - 1
    from jsonb_array_elements(p_data -> 'categorie') with ordinality
  loop
    if coalesce(cat_name, '') = '' then
      raise exception 'Categoria senza nome nel file.';
    end if;

    insert into public.categories (list_id, name, position)
    values (p_list_id, cat_name, cat_pos)
    returning id into cat_id;  -- un nome duplicato viola categories_list_name_uq e annulla tutto

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

revoke all on function public.close_shopping_cart(uuid) from public, anon;
revoke all on function public.import_shopping_list(uuid, jsonb) from public, anon;
grant execute on function public.close_shopping_cart(uuid) to authenticated;
grant execute on function public.import_shopping_list(uuid, jsonb) to authenticated;

-- 4. Residui della vecchia condivisione (sostituita da shopping_list_members).
--    list_shares è vuota; due di queste funzioni erano chiamabili anche senza login.
drop function if exists public.share_list_with_email(uuid, text);
drop function if exists public.has_list_access(uuid);
drop function if exists public.create_shopping_list(text);
drop table if exists public.list_shares;
