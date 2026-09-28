import csv
import glob
import os
import time
from ytmusicapi import YTMusic

# ==========================================
# INNSTILLINGER
# ==========================================

PLAYLIST_DESCRIPTION = "Imported from Spotify CSV"

MAX_RETRIES = 4

# Ventetid mellom normale operasjoner
DELAY = 0.3

# Ventetid etter API-feil
RETRY_DELAY = 3


# ==========================================
# YOUTUBE MUSIC INITIALISERING
# ==========================================

yt = YTMusic("browser.json")


def process_csv_file(csv_path):
    filename = os.path.basename(csv_path)

    # Fjern .csv-etternavn og erstatt understreker med mellomrom
    raw_name = os.path.splitext(filename)[0]
    default_playlist_name = raw_name.replace("_", " ").strip()

    print("=" * 60)
    print(f"BEHANDLER FIL: {filename}")
    print("=" * 60)

    # --------------------------------------
    # 1. LES CSV OGSÅ FINN PLAYLIST NAVN
    # --------------------------------------

    csv_songs = []
    detected_playlist_name = None

    with open(
        csv_path,
        mode="r",
        encoding="utf-8-sig",
        newline=""
    ) as file:

        reader = csv.DictReader(file)

        for row in reader:
            # Sjekk om 'Playlist Name' eller 'Playlist' finnes i kolonnene
            pl_col = row.get("Playlist Name") or row.get("Playlist")
            if pl_col and pl_col.strip() and not detected_playlist_name:
                detected_playlist_name = pl_col.strip()

            artist = row.get("Artist Name(s)", "").strip()
            title = row.get("Track Name", "").strip()

            if not title:
                continue

            csv_songs.append({
                "artist": artist,
                "title": title,
            })

    # Sett endelig navn (enten fra CSV-innhold eller vasket filnavn)
    playlist_name = detected_playlist_name if detected_playlist_name else default_playlist_name
    total_csv = len(csv_songs)

    print(f"Spillelistenavn: '{playlist_name}'")
    print(f"Fant {total_csv} sanger i CSV.\n")

    if total_csv == 0:
        print("Ingen gyldige sanger å behandle. Hopper over filen.\n")
        return

    # --------------------------------------
    # 2. HENT ELLER OPPRETT PLAYLIST
    # --------------------------------------

    print("Sjekker eksisterende spillelister på YT Music...")
    user_playlists = yt.get_library_playlists()
    playlist_id = None
    existing_playlist_items = {}

    for pl in user_playlists:
        if pl.get("title") == playlist_name:
            playlist_id = pl["playlistId"]
            print(f"Fant eksisterende spilleliste: '{playlist_name}' (ID: {playlist_id})")

            # Hent alle spor i eksisterende spilleliste (med setVideoId for sletting)
            playlist_data = yt.get_playlist(playlist_id, limit=None)
            tracks = playlist_data.get("tracks", [])

            for track in tracks:
                vid_id = track.get("videoId")
                set_vid_id = track.get("setVideoId")
                if vid_id and set_vid_id:
                    if vid_id not in existing_playlist_items:
                        existing_playlist_items[vid_id] = []
                    existing_playlist_items[vid_id].append({
                        "videoId": vid_id,
                        "setVideoId": set_vid_id
                    })

            print(f"Fant {len(existing_playlist_items)} unike sanger i spillelisten på YT Music.")
            break

    if not playlist_id:
        playlist_id = yt.create_playlist(
            playlist_name,
            PLAYLIST_DESCRIPTION
        )
        print(f"Opprettet ny spilleliste: '{playlist_name}' (ID: {playlist_id})")

    print()

    # --------------------------------------
    # 3. FASE 1: LEGG TIL NYE & BEHOLD
    # --------------------------------------

    failed_songs = []
    matched_csv_video_ids = set()

    added = 0
    skipped = 0

    print("--- FASE 1: Søker og legger til sanger ---")

    for number, song in enumerate(csv_songs, start=1):

        artist = song["artist"]
        title = song["title"]

        query = f"{artist} {title}".strip()

        print(
            f"[{number}/{total_csv}] "
            f"Søker etter: {query}"
        )

        success = False

        for attempt in range(1, MAX_RETRIES + 1):

            try:

                # Søk etter låt
                search_results = yt.search(
                    query,
                    filter="songs"
                )

                if not search_results:
                    print("    ❌ Fant ikke")
                    failed_songs.append({
                        "artist": artist,
                        "title": title,
                        "reason": "No search results"
                    })
                    break

                track_id = search_results[0]["videoId"]
                matched_csv_video_ids.add(track_id)

                # Sjekk om sangen finnes i YT Music-spillelisten fra før
                if track_id in existing_playlist_items:
                    print("    ⏭️  Finnes allerede i spillelisten (beholdes)")
                    skipped += 1
                    success = True
                    break

                # Legg til
                yt.add_playlist_items(
                    playlist_id,
                    [track_id]
                )

                # Oppdater lokal cache
                existing_playlist_items[track_id] = [{"videoId": track_id, "setVideoId": "NEW"}]
                added += 1

                print("    ✓ Lagt til ny sang")
                success = True
                time.sleep(DELAY)
                break

            except KeyboardInterrupt:
                print("\nSTOPPET AV BRUKER.\n")
                return

            except Exception as e:
                print(f"    ⚠️ API-feil (forsøk {attempt}/{MAX_RETRIES}): {e}")

                if attempt < MAX_RETRIES:
                    wait = RETRY_DELAY * attempt
                    print(f"        Venter {wait}s før nytt forsøk...")
                    time.sleep(wait)
                else:
                    print("    ❌ Hopper over denne sangen.")
                    failed_songs.append({
                        "artist": artist,
                        "title": title,
                        "reason": str(e)
                    })

        if not success:
            print()

    # --------------------------------------
    # 4. FASE 2: SLETT SANGER SOM IKKE ER I CSV
    # --------------------------------------

    print("\n--- FASE 2: Sletter sanger i YT Music som ikke var i CSV ---")

    items_to_remove = []

    for vid_id, items in existing_playlist_items.items():
        if vid_id not in matched_csv_video_ids:
            for item in items:
                if item.get("setVideoId") and item["setVideoId"] != "NEW":
                    items_to_remove.append(item)

    removed_count = 0

    if items_to_remove:
        print(f"Sletter {len(items_to_remove)} spor som var fjernet fra CSV-filen...")
        try:
            yt.remove_playlist_items(playlist_id, items_to_remove)
            removed_count = len(items_to_remove)
            print(f"    ✓ Slettet {removed_count} spor fra spillelisten.")
        except Exception as e:
            print(f"    ❌ Feil under sletting av spor: {e}")
    else:
        print("Ingen spor trengte å bli slettet.")

    # --------------------------------------
    # 5. LAGRE FEILEDE SANGER
    # --------------------------------------

    if failed_songs:
        failed_filename = f"failed_{raw_name}.csv"
        with open(
            failed_filename,
            "w",
            encoding="utf-8",
            newline=""
        ) as file:

            writer = csv.DictWriter(
                file,
                fieldnames=["artist", "title", "reason"]
            )
            writer.writeheader()
            writer.writerows(failed_songs)

    # --------------------------------------
    # OPPSUMMERING FOR DENNE FILEN
    # --------------------------------------

    print(f"\nFERDIG MED: {filename}")
    print(f"- Totalt i CSV:          {total_csv}")
    print(f"- Nye lagt til:          {added}")
    print(f"- Beholdt (uendret):     {skipped}")
    print(f"- Slettet fra YT Music:  {removed_count}")
    print(f"- Feilet/ikke funnet:    {len(failed_songs)}")
    print(f"- Playlist ID:           {playlist_id}\n\n")


# ==========================================
# HOVEDPROGRAM
# ==========================================

if __name__ == "__main__":
    all_csv_files = glob.glob("*.csv")
    csv_files = [f for f in all_csv_files if not f.startswith("failed_")]

    if not csv_files:
        print("Fant ingen .csv-filer i mappen.")
    else:
        print(f"Fant {len(csv_files)} CSV-fil(er) som skal behandles:\n")
        for f in csv_files:
            print(f" - {f}")
        print()

        for csv_file in csv_files:
            process_csv_file(csv_file)

    print("Alle filer er ferdig behandlet.")
