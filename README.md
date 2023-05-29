##### Piotr Trybisz

# IPFSphere

### Komunikator wykorzystujący protokół [IPFS](https://ipfs.tech/)

## Funkcjonalności
- Instalacja IPFS, konfiguracja i uruchomienie go w tle
- Rejestracja użytkownika
- Wylogowanie użytkownika
- Tworzenie pokoju czatu o nazwie wybranej przez użytkownika
- Wyświetlanie listy pokoi czatu, których użytkownik jest członkiem
- Dołączanie do pokoju czatu o podanej nazwie
- Wysyłanie wiadomości do pokoju
- Odczytywanie wiadomości z pokoju

## Działanie
### Automatyczna instalacja
Podczas instalacji ~~(`--install`)~~ *(po wykryciu braku zainstalowanych zależności)*, skrypt pobierze i zainstaluje IPFS, który następnie zostanie uruchomiony jako demon z opcją `--enable-pubsub-experiment`, umożliwiającą publikację i subskrypcję wiadomości.
### Uwierzytelnianie
Jeśli na urządzeniu nie będzie znajdował się plik z kluczem prywatnym użytkownika, zostanie on wygenerowany i zapisany w pliku. Następnie zostanie wyświetlony ekran, na którym użytkownik będzie mógł wymyślić sobie nick. Po wygenerowaniu pary kluczy, klucz publiczny zostanie wystawiony poprzez [IPNS](https://docs.ipfs.tech/concepts/ipns/). ~~Klucze publiczne wszystkich użytkowników wchodzących w interakcje będą zapisywane do pliku. Wiadomości będą szyfrowane kluczem prywatnym użytkownika i kluczem publicznym odbiorcy.
Jeżeli zostanie wykryta zmiana, użytkownik zostanie powiadomiony, że może być to już inna osoba o tym samym nicku.~~ *(TODO)*
Przy wylogowaniu ~~(`--logout`)~~ *(`-r`)*, para kluczy zostanie usunięta z komputera.
### Pokoje czatu
Pokoje czatu zostaną zrealizowane przy użyciu IPFS [PubSub](https://blog.ipfs.tech/25-pubsub/). Przy tworzeniu pokoju użytkownik zostanie poproszony o jego nazwę.

Przy dołączaniu do pokoju czatu, użytkownik zostanie poproszony o nazwę pokoju. Po pomyślnym dołączeniu, pokój zostanie zapisany na liście w pliku.

Lista pokojów czatu zostanie wyświetlona przy uruchomieniu skryptu bez argumentów. Użytkownik będzie mógł wybrać pokój, do którego chce dołączyć.

Wszystkie widoki zostaną zrealizowane z użyciem programu Dialog.