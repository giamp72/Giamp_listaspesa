# Giamp_listaspesa
Web app per lista della spesa con Supabase e GitHub Pages

## Database

Per una nuova installazione, esegui `schema.sql` e `schema_update_quantity.sql`
nel SQL Editor di Supabase. Per aggiornare un database già esistente e abilitare
il salvataggio delle carte fedeltà, esegui `schema_update_loyalty.sql` nello
stesso editor. Per abilitare template/ricorrenze, ordine percorso per lista e
suggerimenti automatici basati sullo storico acquisti, esegui anche
`schema_update_templates_route_suggestions.sql`. Per condividere le liste con
utenti registrati e aggiornamenti in tempo reale, esegui anche
`schema_update_shared_lists.sql`. Il proprietario può invitare o rimuovere
collaboratori dall’elenco Liste usando l’email del loro account. Gli invitati
devono accedere all’app; possono modificare categorie, prodotti e gli articoli
della spesa condivisa. Solo il proprietario può invitare utenti, importare JSON
o eliminare la lista.

## Suggerimenti

Il pulsante **Suggerisci** usa lo storico personale salvato quando si chiude
il carrello. Un prodotto può essere suggerito dopo almeno due acquisti e quando
è trascorso un intervallo sufficiente dall'ultimo acquisto; i prodotti già
presenti nella lista non vengono aggiunti di nuovo.
