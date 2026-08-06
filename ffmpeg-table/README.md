# FFmpeg-Tischserver wieder in Betrieb nehmen

## Installation auf einer neuen Hetzner-VM

Die Datei `ffmpeg-server_cloud-config` im Wurzelverzeichnis übernimmt die
Grundinstallation eines neuen Tischservers. Produktive IP-Adressen und
Streamkeys gehören weder in diese Datei noch in das öffentliche Repository.

```text
MediaMTX-VM bei Hetzner erstellen
→ öffentliche MediaMTX-IP feststellen
→ MediaMTX prüfen
→ MediaMTX-IP einmal lokal eintragen
→ FFmpeg-VMs erstellen
→ FFmpeg-Server zentral konfigurieren
→ Paarungen einspielen
→ Gesamtsystem prüfen
```

## Zentrale Konfiguration nach der Grundinstallation

MediaMTX wird zuerst erstellt und geprüft. Sobald seine öffentliche IP bekannt
ist, wird `deploy/event.env.example` lokal nach `deploy/event.env` kopiert. In
dieser nicht versionierten Datei werden die MediaMTX-IP sowie nach dem Erstellen
der FFmpeg-VMs deren IP-Adressen, Tischnummern, Tisch-Streamkeys und individuelle
Werte für `VIDEO_DELAY` eingetragen.

```bash
cp deploy/event.env.example deploy/event.env
nano deploy/event.env
```

`deploy/event.env` und `deploy/generated/` werden von Git ignoriert. Die
produktiven Werte stehen damit einmal lokal und weder im Repository noch in den
versionierten cloud-init-Dateien.

Anschließend verteilt das Skript die vollständige Konfiguration per SSH auf
alle eingetragenen FFmpeg-Server:

```bash
./deploy/configure-ffmpeg-servers.sh
```

Es erzeugt auf jedem Server `/etc/ffmpeg-table.env` in diesem Format:

```ini
TABLE=1
MEDIAMTX_HOST=MEDIAMTX_SERVER
RTSP_PORT=8554
YOUTUBE_URL=rtmp://a.rtmp.youtube.com/live2
YOUTUBE_KEY=YOUTUBE_STREAM_KEY
VIDEO_DELAY=0.0
```

Für alle Server verwendet es dieselben Werte für `MEDIAMTX_HOST`, `RTSP_PORT`
und `YOUTUBE_URL`. `TABLE`, `YOUTUBE_KEY` und `VIDEO_DELAY` stammen aus dem
jeweiligen Servereintrag. Das Skript überträgt den Key ohne ihn auszugeben,
setzt Besitzer `root:root` und Rechte `600`, startet `ffmpeg-table` und zeigt
den Dienststatus. Eine manuelle Bearbeitung jeder einzelnen Live-Maschine ist
nicht notwendig.

### Paarungen

Den aktuellen Spielplan hier ablegen oder bearbeiten:

```bash
sudo nano /root/overlay/schedule.json
```

Das Feld `table` ordnet jeden Eintrag einem Tisch zu.

Danach:

```bash
sudo systemctl restart overlay-writer
```

cloud-init installiert FFmpeg, Python, Git, die benötigte DejaVu-Schrift und
Zeitzonendaten. Es klont das Repository nach `/opt/showdownBSCPraha2026`, legt
die Laufzeitdateien unter `/usr/local/bin`, `/root/overlay` und `/var/overlays`
ab und installiert beide systemd-Units. Der Overlay-Writer wird aktiviert und
gestartet. `ffmpeg-table` bleibt mit der Platzhalterkonfiguration deaktiviert
und gestoppt; erst das zentrale Deployment-Skript aktiviert und startet ihn.

Wichtige Prüfkommandos:

```bash
systemctl status overlay-writer
systemctl status ffmpeg-table
journalctl -u overlay-writer -f
journalctl -u ffmpeg-table -f
```

## YouTube-Streamkey für die FFmpeg-Variante

Der Key liegt ausschließlich auf dem Server in `/etc/ffmpeg-table.env`:

```ini
YOUTUBE_URL=rtmp://a.rtmp.youtube.com/live2
YOUTUBE_KEY=YOUTUBE_STREAM_KEY
```

`YOUTUBE_URL` ist die gemeinsame Basis-URL und steht in
`/etc/ffmpeg-table.env`. `YOUTUBE_KEY` ist der geheime Key des jeweiligen
Tischstreams. `run-ffmpeg-table.sh` setzt beide als
`"${YOUTUBE_URL}/${YOUTUBE_KEY}"` zur vollständigen Ausgabeadresse zusammen.
Nur der Key ist geheim.

Die Datei nicht in das Repository übernehmen und nur für root lesbar machen:

```bash
sudo chown root:root /etc/ffmpeg-table.env
sudo chmod 600 /etc/ffmpeg-table.env
```

Änderungen werden erneut zentral verteilt; dabei startet das Skript den
FFmpeg-Service neu:

```bash
./deploy/configure-ffmpeg-servers.sh
```

Die Direktweiterleitung über MediaMTX verwendet einen anderen Ablageort; siehe
[`mediamtx-direct-youtube/README.md`](../mediamtx-direct-youtube/README.md).

## Paarungen je Tisch

Der Datenfluss ist:

```text
Turnierplan
→ schedule.json
→ overlay_writer.py
→ table1.txt bis table6.txt
→ FFmpeg-Overlay
```

Im Repository liegt der Spielplan unter `overlay/schedule.json`, auf dem Server
zur Laufzeit unter `/root/overlay/schedule.json`. Jeder JSON-Eintrag enthält
unter anderem Datum (`date`), Uhrzeit (`time`) und Tisch (`table`). `table`
ordnet die Paarung einem Tisch zu; `time` bestimmt den geplanten Beginn.
`overlay_writer.py` liest diese Einträge und erzeugt in `/var/overlays` die
Textdatei des jeweiligen Tisches, die FFmpeg als Overlay einblendet.

Ein kurzer Eintrag sieht beispielsweise so aus:

```json
{
  "date": "2026-03-28",
  "time": "14:00",
  "table": 2,
  "group": "Play-Out",
  "p1": "Spieler 1",
  "p1_nat": "AAA",
  "p2": "Spieler 2",
  "p2_nat": "BBB",
  "ref1": null,
  "ref2": null
}
```

Die ursprüngliche Herkunft beziehungsweise Erstellung der Paarungsdaten ist in
diesem Repository nicht dokumentiert. Der fertige Spielplan muss daher als
passende JSON-Datei bereitgestellt werden.

Der Overlay-Writer lädt `schedule.json` nur beim Start. Nach jeder Änderung:

```bash
sudo systemctl restart overlay-writer
```

## Audio-/Video-Synchronität

Die Korrektur wird in `/etc/ffmpeg-table.env` eingestellt:

```ini
VIDEO_DELAY=0.0
```

`VIDEO_DELAY=0.0` fügt keine Bildverzögerung hinzu. Ein positiver Wert verzögert
das Bild um die angegebene Zahl von Sekunden; `VIDEO_DELAY=0.4` entspricht 400
Millisekunden. Das ist sinnvoll, wenn das Bild dem Ton vorausläuft. Audio wird
mit `-c:a copy` unverändert übernommen; eine separate Audioverzögerung ist
derzeit nicht vorhanden. Läuft das Bild bereits hinter dem Ton, hilft ein
positiver `VIDEO_DELAY` nicht.

Praktischer Abgleich:

1. Einen sichtbaren und hörbaren Impuls aufnehmen, beispielsweise Klatschen.
2. Den Versatz bestimmen.
3. `VIDEO_DELAY` in kleinen Schritten anpassen.
4. Den FFmpeg-Service neu starten.
5. Die Ausgabe erneut kontrollieren.

```bash
sudo systemctl restart ffmpeg-table
```
