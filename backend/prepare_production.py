"""Se ejecuta una vez en el servidor; no muestra la clave privada."""
import argparse
import json
import re
import secrets
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--hostname", required=True, help="Dominio sin https:// ni rutas")
    args = parser.parse_args()
    hostname = args.hostname.strip().lower()
    if not re.fullmatch(r"[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?", hostname) or "." not in hostname:
        parser.error("Indica un dominio válido, por ejemplo usuario.pythonanywhere.com")
    path = Path(__file__).resolve().parent / ".production.json"
    if path.exists():
        parser.error("La configuración ya existe; se conserva para no cambiar la clave.")
    payload = {"secret_key": secrets.token_urlsafe(64), "allowed_hosts": [hostname]}
    with path.open("x", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")
    path.chmod(0o600)
    print("Configuración creada. No compartas el archivo .production.json.")


if __name__ == "__main__":
    main()
