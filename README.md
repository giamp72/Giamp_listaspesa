# Giamp_listaspesa
Web app per lista della spesa con Supabase e GitHub Pages

## Database

Per una nuova installazione, esegui `schema.sql` e `schema_update_quantity.sql`
nel SQL Editor di Supabase. Per aggiornare un database già esistente e abilitare
il salvataggio delle carte fedeltà, esegui `schema_update_loyalty.sql` nello
stesso editor. Per abilitare template/ricorrenze, ordine percorso per lista e
suggerimenti automatici basati sullo storico acquisti, esegui anche
`schema_update_templates_route_suggestions.sql`. Per condividere le liste con
aggiornamenti in tempo reale, esegui anche `schema_update_shared_lists.sql`.
I destinatari devono accedere all’app; le policy RLS attuali consentono a tutti
gli utenti autenticati di vedere e modificare le liste, non solo a chi riceve il link.
