# agents-in-docker-with-dind

Rozszerzenie [agents-in-docker](https://github.com/sigmalko/agents-in-docker): środowisko agenta z dostępem przez SSH, Docker CLI i Docker Compose oraz własnym demonem Docker-in-Docker (DinD). Agent może sam uruchamiać kontenery, np. Redis lub serwery MCP, i budować obrazy. Bazowe repozytorium nadal odpowiada za obraz agenta, jego narzędzia, SSH i większość konfiguracji Compose.

## Jak to działa

```text
Host Docker
├── agent (SSH, Codex, Claude, Docker CLI i Compose)
└── dind (osobny dockerd)
    └── własne obrazy, sieci, wolumeny i kontenery (np. Redis, MCP)

agent:/var/run/docker.sock ── socket Unix ──> dockerd w dind
agent:/workspaces <──────── współdzielony wolumen ────────> dind:/workspaces
```

Compose uruchamia agenta i uprzywilejowany kontener `dind`. Agent łączy się z demonem DinD przez prywatny, współdzielony socket Unix; socket hosta nie jest montowany. Hostowy `docker ps` pokazuje kontenery `agent` i `dind`, ale nie kontenery utworzone przez wewnętrzny demon. `docker ps` u agenta pokazuje kontenery wewnętrzne, a nie kontenery hosta. To rozdzielenie list i zasobów demonów, **nie granica bezpieczeństwa ani izolacja procesów przed administratorem hosta**. Kontenery korzystają ze wspólnego jądra, a `privileged` znacznie osłabia izolację: używaj tylko zaufanych agentów i kodu, najlepiej na osobnej maszynie lub VM. Dostęp do socketu DinD daje pełną kontrolę nad tym demonem.

Demon nie nasłuchuje na porcie TCP API. `/workspaces` jest współdzielony z demonem, aby wewnętrzne bind mounty mogły odwoływać się do tych samych ścieżek. Docker CLI i Compose są dodawane do obrazu bazowego; demon działa w kontenerze `dind`, nie w kontenerze agenta.

## Wymagania i uruchomienie

Wymagane są Git, Docker Engine z obsługą kontenerów uprzywilejowanych i wtyczka Docker Compose v2 na hoście Linux oraz klucz SSH. Zagnieżdżony Docker wymaga odpowiedniej obsługi cgroups, sieci i systemu plików przez hosta. W kontenerach VPS i środowiskach z ograniczeniami uprawnień może nie działać. Obraz upstream musi być dostępny z GHCR.

```bash
git clone --recurse-submodules https://github.com/sigmalko/agents-in-docker-with-dind.git
cd agents-in-docker-with-dind
cp .env.example .env
mkdir -p .ssh
# Skopiuj publiczny klucz SSH z komputera klienta do .ssh/authorized_keys.
chmod 600 .ssh/authorized_keys
# Uzupełnij .env, w szczególności GH_TOKEN i AGENT_REPOSITORY.
./compose up -d --build
./compose ps
```

Jeśli repozytorium zostało sklonowane bez `--recurse-submodules`, wykonaj `git submodule update --init --recursive`. Klucz prywatny pozostaje na komputerze klienta. Zmień porty w `.env`, jeśli są zajęte, następnie połącz się z komputera klienta:

```bash
ssh -i ~/.ssh/agents-in-docker -p 2222 agent@ADRES_HOSTA
```

`SSH_PORT` i `SERVICE_PORT` domyślnie wystawiają porty `2222` i `7777` na wszystkich interfejsach hosta, jak w repozytorium bazowym. Skonfiguruj firewall i dostęp do SSH stosownie do potrzeb. `.env` nie jest wersjonowany; nie umieszczaj w repozytorium tokenów ani kluczy prywatnych. Dalsze informacje o agentach i zmiennych środowiskowych znajdują się w [README repozytorium bazowego](https://github.com/sigmalko/agents-in-docker#readme).

`./compose` przekazuje argumenty do hostowego Docker Compose, łącząc przypięty plik bazowy z `compose.dind.yml` i ustawiając katalog projektu tak, by `.env` i ścieżka do kluczy były rozwiązywane w tym repozytorium. Przykłady: `./compose logs dind`, `./compose restart`, `./compose down`. `IMAGE` wybiera obraz bazowy agenta; domyślne `latest` może się zmienić. Po zmianie obrazu użyj `./compose build --pull` i `./compose up -d`.

## Weryfikacja i przykład Redis

Na hoście `docker ps` pokazuje zewnętrzne kontenery. Po połączeniu przez SSH jako `agent`:

```bash
docker version                 # Server to demon DinD
docker compose version
mkdir -p /workspaces/redis-demo
cd /workspaces/redis-demo
cat > compose.yaml <<'YAML'
services:
  redis:
    image: redis:7-alpine
    ports:
      - "7778:6379"
YAML
docker compose up -d
docker compose exec redis redis-cli ping  # PONG
docker ps                                  # wewnętrzny Redis
```

Z agenta dostęp do opublikowanego portu wewnętrznego jest pod adresem `dind:7778`, np. `node -e 'const s=require("net").connect(7778,"dind",()=>s.write("*1\r\n$4\r\nPING\r\n")); s.on("data",b=>{console.log(b.toString());s.end()})'`. Porty kontenerów wewnętrznych są publikowane w przestrzeni sieciowej `dind`, nie agenta ani bezpośrednio hosta. Zewnętrzne Compose mapuje `127.0.0.1:${DIND_SERVICE_PORT:-7778}` hosta na port `7778` kontenera `dind`; na hoście Redis jest więc domyślnie osiągalny tylko pod `127.0.0.1:7778`. Wewnętrzne mapowanie powinno nasłuchiwać na `0.0.0.0` w `dind`, jak w przykładzie. Inne porty wymagają dodatkowego mapowania w `compose.dind.yml`; sam `docker run -p` wewnątrz nie otwiera ich na hoście. Dla usług dostępnych wyłącznie agentowi nie trzeba dodawać mapowania hosta; w razie potrzeby dostosuj lub usuń domyślne mapowanie.

Wewnętrzne bind mounty są rozwiązywane przez demon `dind`, nie przez klienta Docker. Używaj ścieżek w `/workspaces`, które są dostępne pod tą samą nazwą w obu kontenerach. Przykładowo, po utworzeniu `/workspaces/data` przez agenta `docker run --rm -v /workspaces/data:/data alpine ls /data` widzi ten katalog. Inne ścieżki z kontenera agenta nie są automatycznie dostępne dla demona. Kontekst `docker build` jest przesyłany demonowi przez klienta.

Serwer MCP obsługujący stdio można uruchomić jako proces `docker run --rm -i ...` w konfiguracji klienta MCP. Dla MCP przez HTTP uruchom kontener wewnętrzny z portem i skonfiguruj klienta na `http://dind:PORT`; dobór obrazu, argumentów i autoryzacji zależy od serwera. Serwisy w tej samej wewnętrznej sieci Compose mogą również komunikować się po nazwach usług.

Po przykładzie: `docker compose down` w `/workspaces/redis-demo`.

## Dane, aktualizacja i sprzątanie

Wolumeny hostowego Compose przechowują `/workspaces`, dane demona `dind` i klucze hosta SSH; przetrwają `./compose down` oraz odtworzenie kontenerów. To zmiana względem nietrwałego `/workspaces` w projekcie bazowym. Kontenery, obrazy, cache i wolumeny wewnętrzne zajmują miejsce na dysku hosta. Konfiguracja CLI i loginy w pozostałej części systemu plików agenta pozostają nietrwałe po jego odtworzeniu. `./compose down -v` **usuwa** te wolumeny, w tym workspace, kontenery i dane DinD oraz klucze hosta SSH; przed wykonaniem zapisz potrzebne dane.

## Zależność od agents-in-docker

`upstream/` to [submoduł Git](https://git-scm.com/docs/gitsubmodules), przypięty do konkretnego commitu repozytorium bazowego. Dzięki temu plik Compose upstream jest używany bez kopiowania i aktualizowany świadomie, a GitHub pokazuje link do repozytorium oraz konkretną wersję. Obraz bazowy jest odrębną zależnością: `IMAGE` domyślnie wskazuje ruchomy tag `latest`, więc przypięty submoduł nie przypina obrazu. Aby powtarzalnie wdrażać kompatybilny obraz, ustaw `IMAGE` na konkretny tag lub digest upstream.

Aby zaktualizować zależność konfiguracji, wykonaj `git submodule update --remote upstream`, przejrzyj zmianę commitu, sprawdź zgodność z wybranym obrazem i uruchom środowisko ponownie; następnie zatwierdź nowy wskaźnik submodułu. `compose.dind.yml` nakłada tylko zmiany potrzebne dla DinD. Przy aktualizacjach sprawdź zwłaszcza nazwę usługi `agent`, UID/GID konta `agent` (1000), ścieżkę `/workspaces`, ustawienia SSH oraz zgodność GID socketu `2375` z obrazem `docker:29-dind`. Wykres zależności GitHub dotyczy obsługiwanych manifestów i zgłoszeń przez API; sam submoduł lub wpis w README nie gwarantuje pojawienia się w dependency graph ([dokumentacja GitHub](https://docs.github.com/en/code-security/concepts/supply-chain-security/dependency-graph)).

## Ograniczenia

DinD wymaga zasobów na drugi demon i jego obrazy, może działać wolniej oraz wymaga ostrożności przy portach, uprawnieniach i bind mountach. Usługi współdzielą jądro hosta; host ma dostęp do procesów, danych i sieci, a uprzywilejowany DinD nie nadaje się do uruchamiania niezaufanego kodu jako zabezpieczenie hosta. W przypadku niezaufanych zadań rozważ osobne VM lub inne silniejsze granice izolacji. Więcej: [Docker Engine security](https://docs.docker.com/engine/security/) i [oficjalny obraz Docker](https://hub.docker.com/_/docker).
