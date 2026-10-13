from pathlib import Path
import base64
import binascii
import brotli
import zipfile

root = Path(r"C:\Users\LENOVO\Desktop\QB-R2")
target = b'template-id="questionBoard"'

for archive in sorted(root.rglob("*.zip")):
    try:
        with zipfile.ZipFile(archive) as zf:
            members = zf.namelist()
            normalize = lambda n: n.replace("\\", "/").lstrip("./").rsplit("/", 1)[-1]
            index_name = next((n for n in members if normalize(n) == "index.xml"), None)
            if index_name is None:
                continue
            raw = zf.read(index_name)
            try:
                compressed = base64.b64decode(b"".join(raw.split()), validate=True)
                decoded = brotli.decompress(compressed)
                continue
            except Exception as exc:
                print(f"{archive}")
                print(f"  index bytes: {len(raw)}; starts with: {raw[:80]!r}")
                print(f"  target in raw index: {target in raw}")
                try:
                    plain_b64 = base64.b64decode(b"".join(raw.split()), validate=True)
                    print(f"  decoded Base64 bytes: {len(plain_b64)}; target there: {target in plain_b64}")
                    print(f"  decoded Base64 start: {plain_b64[:80]!r}")
                except (binascii.Error, ValueError) as b64_exc:
                    print(f"  Base64 decode error: {b64_exc}")
                print(f"  Brotli error: {exc}")
    except Exception as exc:
        print(f"{archive}")
        print(f"  ZIP error: {exc}")
