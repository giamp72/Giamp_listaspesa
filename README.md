# Giamp_listaspesa
Web app per lista della spesa con Supabase e GitHub Pages

Per abilitare la condivisione, limitare le liste al proprietario e agli utenti invitati e consentire la creazione delle liste, esegui `schema_update_sharing.sql` nel SQL Editor di Supabase anche se lo schema precedente era già installato. Eseguilo di nuovo per aggiornare installazioni che hanno già ricevuto una versione precedente del file. Per una nuova installazione, usa `schema.sql`.

Perché i link di conferma email tornino all'app, in Supabase apri **Authentication → URL Configuration** e imposta **Site URL** sull'indirizzo GitHub Pages dell'app. Aggiungi lo stesso URL dell'app, incluso il percorso del repository, a **Redirect URLs** (ad esempio `https://<utente>.github.io/<repository>/`). L'app richiede questo URL come destinazione al momento della registrazione.
