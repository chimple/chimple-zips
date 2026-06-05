import zipfile
import re
import hashlib
import mimetypes
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import Request, urlopen

PROJECT_FOLDER = r"/home/santhosh/Documents/GitHub/chimple-zips/"

UPDATED_FOLDER = "updated"
REPORT_FILE = "report.txt"
DOWNLOAD_FOLDER = "assets/downloaded"

URL_RE = re.compile(r'https?://[^\s"\'<>\\)]+', re.IGNORECASE)

ALLOWED_EXTENSIONS = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg",
    ".mp3", ".wav", ".ogg", ".m4a", ".aac"
}

DOWNLOAD_URL_OVERRIDES = {
    "https://aeakbcdznktpsbrfsgys.supabase.co/storage/v1/object/public/template-assets/fill-upAudio.mp3": (
        "https://db-stage.chimple.net/storage/v1/object/public/template-assets/fill-in-the-blanks/fillupEn.mp3"
    ),
}

ZIP_TARGETS = {
    "LIDO_hi1200.zip": "data.json",
    "LIDO_maths3005_hi.zip": "data.json",
    "assess_maths0012.zip": "index.xml",
    "LIDO_en1005.zip": "data.json",
    "assess_hi0004.zip": "index.xml",
    "LIDO_en3413.zip": "data.json",
    "LIDO_maths0004_kn.zip": "data.json",
    "LIDO_en3408.zip": "data.json",
    "assess_maths0011.zip": "index.xml",
    "LIDO_en2608.zip": "data.json",
    "LIDO_en1500.zip": "data.json",
    "LIDO_maths0202_kn.zip": "data.json",
    "845c7b2c-fb7e-4b84-9806-72a6ca35fcc9.zip": "index.xml",
    "LIDO_maths0504_kn.zip": "data.json",
    "d76af362-b21e-4981-8bda-799ff57d874e.zip": "index.xml",
    "assess_maths0002.zip": "index.xml",
    "LIDO_en1608.zip": "data.json",
    "LIDO_maths3001_en.zip": "data.json",
    "LIDO_maths0503_kn.zip": "data.json",
    "LIDO_en1107.zip": "data.json",
    "61f03448-fc7e-4030-bd50-67af3a35d2d5.zip": "index.xml",
    "LIDO_en1708.zip": "data.json",
    "LIDO_kn4600.zip": "data.json",
    "LIDO_maths3010_en.zip": "data.json",
    "assess_maths0004.zip": "index.xml",
    "LIDO_en2101.zip": "data.json",
    "09a10bea-9c01-48d4-909b-7fcfe4664108.zip": "index.xml",
    "LIDO_maths0101_kn.zip": "data.json",
    "be1804a3-e420-4662-8f18-8862a127c966.zip": "index.xml",
    "LIDO_hi0108.zip": "data.json",
    "mz_pt5_0004.zip": "index.xml",
    "assess_maths0006.zip": "index.xml",
    "LIDO_kn0507.zip": "data.json",
    "LIDO_maths3004_hi.zip": "data.json",
    "assess_maths0008.zip": "index.xml",
    "assess_maths0010.zip": "index.xml",
    "LIDO_en1606.zip": "data.json",
    "LIDO_maths3006_en.zip": "data.json",
    "LIDO_maths0304_kn.zip": "data.json",
    "d108024b-7c51-4564-90f8-d9ea90dc27c6.zip": "index.xml",
    "LIDO_en2103.zip": "data.json",
    "LIDO_kn2_0703.zip": "data.json",
    "LIDO_maths3002_en.zip": "data.json",
    "LIDO_maths2621_en.zip": "data.json",
    "assess_maths0013.zip": "index.xml",
    "LIDO_en3702.zip": "data.json",
    "LIDO_hi_3408.zip": "data.json",
    "Comprehension_Skills.zip": "index.xml",
    "LIDO_kn4310.zip": "data.json",
    "LIDO_kn4504.zip": "data.json",
    "assess_maths0001.zip": "index.xml",
    "assess_maths0000.zip": "index.xml",
    "assess_hi0003.zip": "index.xml",
    "LIDO_en0902.zip": "data.json",
    "assess_maths0009.zip": "index.xml",
    "LIDO_maths3000_en.zip": "data.json",
    "LIDO_maths0201_kn.zip": "data.json",
    "LIDO_maths0003_kn.zip": "data.json",
    "LIDO_maths0509_en.zip": "data.json",
    "LIDO_hi1202.zip": "data.json",
    "assess_en0003.zip": "index.xml",
    "assess_maths0014.zip": "index.xml",
    "LIDO_en_5116.zip": "data.json",
    "HN_NC_00008.zip": "data.json",
    "LIDO_en2403.zip": "data.json",
    "LIDO_maths3004_en.zip": "data.json",
    "LIDO_en1610.zip": "data.json",
    "LIDO_en1505.zip": "data.json",
    "LIDO_en1503.zip": "data.json",
    "c3002e52-6e5b-4b32-a69f-274634b45825.zip": "index.xml",
    "assess_maths0007.zip": "index.xml",
    "mz_pt5_0003.zip": "index.xml",
    "LIDO_maths3009_en.zip": "data.json",
    "assess_hi0002.zip": "index.xml",
    "LIDO_maths0204_kn.zip": "data.json",
    "LIDO_maths0200_kn.zip": "data.json",
    "LIDO_maths3003_en.zip": "data.json",
    "da8fdef0-3147-48ad-9cb2-20e5101f81dc.zip": "index.xml",
    "LIDO_en0908.zip": "data.json",
    "LIDO_en1800.zip": "data.json",
    "LIDO_kn4608.zip": "data.json",
    "LIDO_maths3005_en.zip": "data.json",
    "LIDO_maths0300_kn.zip": "data.json",
    "LIDO_maths3003_kn.zip": "data.json",
    "LIDO_maths2620_en.zip": "data.json",
    "LIDO_maths0500_kn.zip": "data.json",
    "4d1b6113-fe89-41ce-a1ee-39e02fdd36cc.zip": "index.xml",
    "LIDO_maths0001_kn.zip": "data.json",
    "mz_pt5_0001.zip": "index.xml",
    "LIDO_en1103.zip": "data.json",
    "LIDO_en_5212.zip": "data.json",
    "LIDO_maths0002_kn.zip": "data.json",
    "745b36a4-1405-464d-85f4-3f0ece7341e2.zip": "index.xml",
    "assess_maths0005.zip": "index.xml",
    "assess_en0004.zip": "index.xml",
    "assess_maths0003.zip": "index.xml",
    "pwc_0023.zip": "index.xml",
    "LIDO_maths0000_kn.zip": "data.json",
    "LIDO_maths3008_en.zip": "data.json",
    "LIDO_maths3007_en.zip": "data.json",
}


def safe_filename(url, content_type=None):
    parsed = urlparse(url)
    name = Path(parsed.path).name
    ext = Path(name).suffix.lower()

    if name and ext in ALLOWED_EXTENSIONS:
        return name

    if content_type:
        guessed_ext = mimetypes.guess_extension(content_type.split(";")[0].strip())
        if guessed_ext in ALLOWED_EXTENSIONS:
            return hashlib.md5(url.encode()).hexdigest() + guessed_ext

    return None


def download_file(url):
    try:
        req = Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urlopen(req, timeout=30) as response:
            content_type = response.headers.get("Content-Type", "")
            filename = safe_filename(url, content_type)

            if not filename:
                return None, None, "unsupported image/audio type"

            data = response.read()

            if not data:
                return None, None, "empty download"

            return filename, data, None

    except Exception as e:
        return None, None, str(e)


def unique_path(path, existing_paths):
    p = Path(path)
    parent = p.parent.as_posix()
    stem = p.stem
    suffix = p.suffix

    final = path
    count = 1

    while final in existing_paths:
        final = f"{parent}/{stem}_{count}{suffix}"
        count += 1

    return final

def clean_url(url):
    return url.rstrip(';,\'"')

def split_download_url(url):
    download_url = clean_url(url)
    trailing_text = url[len(download_url):]
    return download_url, trailing_text

def resolve_download_url(url):
    return DOWNLOAD_URL_OVERRIDES.get(url, url)

def process_zip(zip_path, target_file, output_zip, report_lines):
    changed_files = {}
    downloaded_files = {}
    replacements = {}

    with zipfile.ZipFile(zip_path, "r") as zin:
        items = zin.infolist()
        existing_paths = {item.filename for item in items}

        matching_items = [
            item for item in items
            if Path(item.filename).name == target_file
        ]

        if not matching_items:
            msg = "target file not inside zip"
            print(f"  FILE NOT FOUND: {target_file}")
            report_lines.append(
                f"{zip_path.name} | {target_file} | FILE_NOT_FOUND | | | {msg}"
            )
            return False

        total_urls = 0
        url_entries = []

        for info in matching_items:
            text = zin.read(info.filename).decode("utf-8", errors="ignore")
            urls = URL_RE.findall(text)
            total_urls += len(urls)
            url_entries.append((info, text, urls))

        if total_urls == 0:
            print("  No URLs found")
            report_lines.append(
                f"{zip_path.name} | {target_file} | NO_URL_FOUND | | | no http/https urls"
            )
            return False

        done_urls = 0

        for info, text, urls in url_entries:
            for raw_url in urls:
                url, trailing_text = split_download_url(raw_url)
                download_url = resolve_download_url(url)
                done_urls += 1
                url_percent = round((done_urls / total_urls) * 100, 2)

                if download_url in replacements:
                    replacement_path = replacements[download_url] + trailing_text
                    text = text.replace(raw_url, replacement_path)
                    print(f"  [{url_percent}%] REUSED: {url}")
                    if download_url != url:
                        print(f"       using override: {download_url}")
                    note = "reused previous download"
                    if download_url != url:
                        note = f"{note}; downloaded from {download_url}"
                    report_lines.append(
                        f"{zip_path.name} | {info.filename} | REUSED | {raw_url} | {replacement_path} | {note}"
                    )
                    continue
                
                downloaded_name, data, error = download_file(download_url)

                if not downloaded_name or not data:
                    print(f"  [{url_percent}%] FAILED: {url}")
                    if download_url != url:
                        print(f"       using override: {download_url}")
                        error = f"{error}; download url: {download_url}"
                    report_lines.append(
                        f"{zip_path.name} | {info.filename} | FAILED | {raw_url} | | {error}"
                    )
                    continue

                local_path = f"{DOWNLOAD_FOLDER}/{downloaded_name}"
                local_path = unique_path(
                    local_path,
                    existing_paths | set(downloaded_files.keys())
                )

                downloaded_files[local_path] = data
                existing_paths.add(local_path)
                replacements[download_url] = local_path

                replacement_path = local_path + trailing_text
                text = text.replace(raw_url, replacement_path)

                print(f"  [{url_percent}%] DOWNLOADED: {url}")
                if download_url != url:
                    print(f"       using override: {download_url}")
                print(f"       -> {replacement_path}")

                note = "downloaded and replaced"
                if download_url != url:
                    note = f"downloaded from {download_url} and replaced"
                report_lines.append(
                    f"{zip_path.name} | {info.filename} | SUCCESS | {raw_url} | {replacement_path} | {note}"
                )

            changed_files[info.filename] = text.encode("utf-8")

        if not downloaded_files:
            print("  No files downloaded, zip not created")
            return False

        print("  Writing updated ZIP...")

        with zipfile.ZipFile(output_zip, "w", zipfile.ZIP_DEFLATED) as zout:
            total_items = len(items) + len(downloaded_files)
            written = 0

            for info in items:
                if info.filename in changed_files:
                    zout.writestr(info, changed_files[info.filename])
                else:
                    zout.writestr(info, zin.read(info.filename))

                written += 1
                percent = round((written / total_items) * 100, 2)
                print(f"    ZIP write {percent}%")

            for local_path, data in downloaded_files.items():
                zout.writestr(local_path, data)

                written += 1
                percent = round((written / total_items) * 100, 2)
                print(f"    ZIP write {percent}%")

    return True


def main():
    project = Path(PROJECT_FOLDER)
    updated = project / UPDATED_FOLDER
    updated.mkdir(exist_ok=True)

    report_lines = ["zip | file | status | url | local_path | note"]

    total_zips = len(ZIP_TARGETS)
    updated_count = 0
    failed_count = 0
    skipped_count = 0

    for index, (zip_name, target_file) in enumerate(ZIP_TARGETS.items(), start=1):
        overall_percent = round((index / total_zips) * 100, 2)

        print()
        print("=" * 80)
        print(f"[{index}/{total_zips}] {overall_percent}% - {zip_name}")
        print(f"Target file: {target_file}")
        print("=" * 80)

        zip_path = project / zip_name
        output_zip = updated / zip_name

        if not zip_path.exists():
            print("ZIP NOT FOUND")
            skipped_count += 1
            report_lines.append(
                f"{zip_name} | {target_file} | ZIP_NOT_FOUND | | | zip file missing"
            )
            continue

        try:
            changed = process_zip(zip_path, target_file, output_zip, report_lines)

            if changed:
                updated_count += 1
                print(f"UPDATED: {zip_name}")
            else:
                skipped_count += 1
                if output_zip.exists():
                    output_zip.unlink()
                print(f"SKIPPED: {zip_name}")

        except Exception as e:
            failed_count += 1
            report_lines.append(
                f"{zip_name} | {target_file} | ZIP_FAILED | | | {e}"
            )
            print(f"FAILED: {zip_name} -> {e}")

    report_path = updated / REPORT_FILE

    with open(report_path, "w", encoding="utf-8") as f:
        f.write("\n".join(report_lines))

    print()
    print("=" * 80)
    print("DONE")
    print("=" * 80)
    print(f"Total ZIPs listed: {total_zips}")
    print(f"Updated ZIPs: {updated_count}")
    print(f"Skipped ZIPs: {skipped_count}")
    print(f"Failed ZIPs: {failed_count}")
    print(f"Updated folder: {updated}")
    print(f"Report file: {report_path}")


if __name__ == "__main__":
    main()
