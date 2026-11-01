create table if not exists loyalty_cards (
  user_id uuid primary key references auth.users(id) on delete cascade,
  image_data text not null,
  updated_at timestamptz not null default now()
);

alter table loyalty_cards enable row level security;

drop policy if exists "users manage own loyalty card" on loyalty_cards;

create policy "users manage own loyalty card"
on loyalty_cards
for all
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

grant select, insert, update, delete on table loyalty_cards to authenticated;
