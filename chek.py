import zipfile
import re
import hashlib
import mimetypes
import base64
import subprocess
from pathlib import Path
from urllib.parse import unquote, urlparse
from urllib.request import Request, urlopen

PROJECT_FOLDER = r"/home/santhosh/Documents/GitHub/chimple-zips/"

UPDATED_FOLDER = "updated"
REPORT_FILE = "report.txt"
DOWNLOAD_FOLDER = "assets/downloaded"

URL_RE = re.compile(r'https?://[^"\'<>\\]+', re.IGNORECASE)
BASE64_TEXT_RE = re.compile(r'^[A-Za-z0-9+/=\s]+$')

TARGET_URL_PREFIXES = (
    (
        "https://aeakbcdznktpsbrfsgys.supabase.co/storage/v1/object/public/"
        "template-assets/Ordered%20Tractor/trolly_drop_soundtrain_base%20(1"
    ),
    (
        "https://aeakbcdznktpsbrfsgys.supabase.co/storage/v1/object/public/"
        "template-assets/create%20sentence/truck%20(3"
    ),
)

ALLOWED_EXTENSIONS = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg",
    ".mp3", ".wav", ".ogg", ".m4a", ".aac", ".riv"
}

DOWNLOAD_URL_OVERRIDES = {
    "https://aeakbcdznktpsbrfsgys.supabase.co/storage/v1/object/public/template-assets/fill-upAudio.mp3": (
        "https://db-stage.chimple.net/storage/v1/object/public/template-assets/fill-in-the-blanks/fillupEn.mp3"
    ),
}

TARGET_FILE_NAMES = {"data.json", "index.xml"}


def safe_filename(url, content_type=None):
    parsed = urlparse(url)
    name = sanitize_filename(Path(unquote(parsed.path)).name)
    ext = Path(name).suffix.lower()

    if name and ext in ALLOWED_EXTENSIONS:
        return name

    if content_type:
        guessed_ext = mimetypes.guess_extension(content_type.split(";")[0].strip())
        if guessed_ext in ALLOWED_EXTENSIONS:
            return hashlib.md5(url.encode()).hexdigest() + guessed_ext

    return None


def sanitize_filename(name):
    cleaned = unquote(name)
    cleaned = re.sub(r"\s+", "", cleaned)
    cleaned = cleaned.replace("%20", "")
    cleaned = re.sub(r"[^A-Za-z0-9._()-]", "", cleaned)
    return cleaned


def is_target_url(url):
    return any(url.startswith(prefix) for prefix in TARGET_URL_PREFIXES)


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

def brotli_decompress(data):
    try:
        import brotli  # type: ignore
        return brotli.decompress(data)
    except ImportError:
        pass

    script = """
const zlib = require('zlib');
const chunks = [];
process.stdin.on('data', chunk => chunks.push(chunk));
process.stdin.on('end', () => {
  const data = Buffer.concat(chunks);
  process.stdout.write(zlib.brotliDecompressSync(data));
});
"""
    result = subprocess.run(
        ["node", "-e", script],
        input=data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    return result.stdout

def brotli_compress(data):
    try:
        import brotli  # type: ignore
        return brotli.compress(data)
    except ImportError:
        pass

    script = """
const zlib = require('zlib');
const chunks = [];
process.stdin.on('data', chunk => chunks.push(chunk));
process.stdin.on('end', () => {
  const data = Buffer.concat(chunks);
  process.stdout.write(zlib.brotliCompressSync(data));
});
"""
    result = subprocess.run(
        ["node", "-e", script],
        input=data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    return result.stdout

def decode_brotli_base64(text):
    normalized = (
        text.strip()
        .removeprefix("data:;base64,")
        .replace("\\n", "")
        .replace("-", "+")
        .replace("_", "/")
    )
    normalized = re.sub(r"\s+", "", normalized)
    normalized += "=" * (-len(normalized) % 4)
    compressed = base64.b64decode(normalized)
    return brotli_decompress(compressed).decode("utf-8")

def encode_brotli_base64(text):
    compressed = brotli_compress(text.encode("utf-8"))
    return base64.b64encode(compressed).decode("ascii")

def read_text_file(zin, filename):
    data = zin.read(filename)
    text = data.decode("utf-8", errors="ignore")

    if "http://" in text or "https://" in text:
        return text, None, None

    stripped = text.strip()
    if (
        stripped
        and len(stripped) >= 128
        and len(stripped) % 4 == 0
        and BASE64_TEXT_RE.fullmatch(stripped)
    ):
        try:
            return decode_brotli_base64(stripped), "brotli_base64", None
        except Exception as e:
            return text, "encoded_unknown", str(e)

    return text, None, None

def encode_text_file(text, codec):
    if codec == "brotli_base64":
        return encode_brotli_base64(text).encode("utf-8")

    return text.encode("utf-8")

def get_file_codec(zin, filename):
    _, codec, _ = read_text_file(zin, filename)
    return codec

def process_zip(zip_path, target_files, output_zip, report_lines, external_texts=None):
    changed_files = {}
    downloaded_files = {}
    replacements = {}
    external_texts = external_texts or {}
    target_label = ",".join(sorted(target_files))

    with zipfile.ZipFile(zip_path, "r") as zin:
        items = zin.infolist()
        existing_paths = {item.filename for item in items}

        matching_items = [
            item for item in items
            if Path(item.filename).name in target_files
        ]

        if not matching_items:
            msg = "target files not inside zip"
            print(f"  FILE NOT FOUND: {target_label}")
            report_lines.append(
                f"{zip_path.name} | {target_label} | FILE_NOT_FOUND | | | {msg}"
            )
            return False

        total_urls = 0
        url_entries = []
        encoded_files = []
        file_codecs = {}

        for info in matching_items:
            if info.filename in external_texts:
                text = external_texts[info.filename]
                codec = get_file_codec(zin, info.filename)
                encoding_note = None
                print(f"  Using external decoded file for {info.filename}")
            else:
                text, codec, encoding_note = read_text_file(zin, info.filename)
            urls = [
                url
                for url in URL_RE.findall(text)
                if is_target_url(clean_url(url))
            ]
            total_urls += len(urls)
            url_entries.append((info, text, urls))
            file_codecs[info.filename] = codec
            if encoding_note and not urls:
                encoded_files.append((info.filename, encoding_note))

        if total_urls == 0:
            if encoded_files:
                for filename, encoding_note in encoded_files:
                    msg = f"file looks encoded but Brotli/base64 decode failed: {encoding_note}"
                    print(f"  ENCODED FILE: {filename}")
                    report_lines.append(
                        f"{zip_path.name} | {filename} | ENCODED_FILE | | | {msg}"
                    )
                return False

            print("  No URLs found")
            report_lines.append(
                f"{zip_path.name} | {target_label} | NO_URL_FOUND | | | no http/https urls"
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

            changed_files[info.filename] = encode_text_file(
                text,
                file_codecs.get(info.filename),
            )

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

    zip_paths = sorted(project.glob("*.zip"))
    total_zips = len(zip_paths)
    updated_count = 0
    failed_count = 0
    skipped_count = 0

    if total_zips == 0:
        print(f"No ZIP files found in {project}")

    for index, zip_path in enumerate(zip_paths, start=1):
        zip_name = zip_path.name
        target_label = ",".join(sorted(TARGET_FILE_NAMES))
        overall_percent = round((index / total_zips) * 100, 2)

        print()
        print("=" * 80)
        print(f"[{index}/{total_zips}] {overall_percent}% - {zip_name}")
        print(f"Target files: {target_label}")
        print("=" * 80)

        output_zip = updated / zip_name

        try:
            changed = process_zip(zip_path, TARGET_FILE_NAMES, output_zip, report_lines)

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
                f"{zip_name} | {target_label} | ZIP_FAILED | | | {e}"
            )
            print(f"FAILED: {zip_name} -> {e}")

    report_path = updated / REPORT_FILE

    with open(report_path, "w", encoding="utf-8") as f:
        f.write("\n".join(report_lines))

    print()
    print("=" * 80)
    print("DONE")
    print("=" * 80)
    print(f"Total ZIPs found: {total_zips}")
    print(f"Updated ZIPs: {updated_count}")
    print(f"Skipped ZIPs: {skipped_count}")
    print(f"Failed ZIPs: {failed_count}")
    print(f"Updated folder: {updated}")
    print(f"Report file: {report_path}")


if __name__ == "__main__":
    main()
