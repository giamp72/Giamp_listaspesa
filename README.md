# Giamp_listaspesa
Web app per lista della spesa con Supabase e GitHub Pages

## Database

**Nuova installazione:** esegui `schema.sql` nel SQL Editor di Supabase. Il file
contiene tutto lo schema (tabelle, funzioni, policy di sicurezza, realtime e
bucket delle foto) allineato al database in produzione.

**Database esistente:** esegui in ordine i file della cartella `migrations/` non
ancora applicati. Sono rieseguibili senza effetti collaterali.

Il proprietario può invitare o rimuovere collaboratori dall’elenco Liste usando
l’email del loro account. Gli invitati devono accedere all’app; possono
modificare categorie, prodotti e gli articoli della spesa condivisa. Solo il
proprietario può invitare utenti, importare JSON o eliminare la lista.

## Test

```
node --test tests/*.cjs
```

## Suggerimenti

Il pulsante **Suggerisci** usa lo storico personale salvato quando si chiude
il carrello. Un prodotto può essere suggerito dopo almeno due acquisti e quando
è trascorso un intervallo sufficiente dall'ultimo acquisto; i prodotti già
presenti nella lista non vengono aggiunti di nuovo.
