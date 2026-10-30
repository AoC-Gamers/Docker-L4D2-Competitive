"""Sonar evidence helpers adapted from BanSystem-Backend; no runtime dependencies."""
from __future__ import annotations
import hashlib,json,os,re,subprocess,tempfile
from pathlib import Path
from typing import Any,Callable
from urllib.parse import urlsplit

class SonarToolError(RuntimeError):
    """Safe diagnostic, never include credentials or remote response bodies."""

def validate_origin(value: str) -> str:
    try:
        u = urlsplit(value)
        if (u.scheme != "https" or not u.hostname or u.username is not None
                or u.password is not None or u.query or u.fragment
                or u.path not in ("", "/") or not u.port and u.netloc.endswith(":")):
            raise ValueError()
        return f"https://{u.netloc}".rstrip("/")
    except ValueError:
        raise SonarToolError("SONAR_HOST_URL requiere origen HTTPS local sin credenciales, ruta, query ni fragmento.") from None

def paging_total(payload: dict[str, Any], _collection: str = "") -> int:
    paging = payload.get("paging", {})
    if not isinstance(paging, dict):
        raise SonarToolError("Sonar: paginacion invalida.")
    values = [v for v in (payload.get("total"), paging.get("total")) if v is not None]
    if not values or any(type(v) is not int or v < 0 for v in values) or len(set(values)) != 1:
        raise SonarToolError("Sonar: total de paginacion ausente, invalido o discordante.")
    return values[0]

def paginate(request: Callable, base: str, token: str, path: str,
             params: dict[str, Any], collection: str, project: str) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    seen: set[str] = set()
    total = None
    for page in range(1, 20002):
        payload = request(base, token, path, {**params, "ps": 500, "p": page})
        count = paging_total(payload)
        if total is not None and total != count:
            raise SonarToolError("Sonar: total cambio entre paginas.")
        total = count
        paging = payload.get("paging", {})
        if ("pageIndex" in paging and paging["pageIndex"] != page
                or "pageSize" in paging and paging["pageSize"] != 500):
            raise SonarToolError("Sonar: pagina o tamano discordante.")
        batch = payload.get(collection)
        if not isinstance(batch, list) or len(batch) > 500 or (not batch and len(items) != total):
            raise SonarToolError("Sonar: coleccion invalida o pagina vacia prematura.")
        for item in batch:
            if not isinstance(item, dict) or not isinstance(item.get("key"), str) or not item["key"]:
                raise SonarToolError("Sonar: item sin clave unica.")
            key = item["key"]
            if key in seen:
                raise SonarToolError("Sonar: clave duplicada entre paginas.")
            if (collection != "components" and item.get("project") != project) or ("component" in item and (not isinstance(item["component"], str) or not item["component"].startswith(project + ":"))):
                raise SonarToolError("Sonar: item de otro proyecto.")
            if collection == "components" and not key.startswith(project + ":"):
                raise SonarToolError("Sonar: componente de otro proyecto.")
            seen.add(key)
            items.append(item)
        if len(items) > total:
            raise SonarToolError("Sonar: mas items que el total declarado.")
        if len(items) == total:
            return items
    raise SonarToolError("Sonar: limite de paginas excedido; no se publica reporte parcial.")

def file_hash(path: Path) -> str:
    if not path.is_file() or path.is_symlink():
        raise SonarToolError("Sonar: falta artefacto regular de evidencia.")
    return hashlib.sha256(path.read_bytes()).hexdigest()

def source_identity(root: Path) -> dict[str, Any]:
    names = subprocess.check_output(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=root).decode().split("\0")
    files = {}
    for name in sorted(set(names)):
        if not name:
            continue
        path = root / name
        if path.is_symlink():
            raise SonarToolError("Sonar: fuente symlink no admitida; no puede demostrar identidad del target.")
        elif path.is_file():
            files[name] = file_hash(path)
        else:
            files[name] = "deleted"
    # Includes dirty/untracked, non-ignored source, tests, config and documentation.
    fingerprint = hashlib.sha256(json.dumps(files, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    return {"sha256": fingerprint, "files": files}

def atomic_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=".sonar-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, indent=2, ensure_ascii=False)
            stream.write("\n")
        os.replace(temp, path)
    finally:
        Path(temp).unlink(missing_ok=True)

def read_task(path: Path, base: str, project: str) -> dict[str, str]:
    values = {}
    if not path.is_file() or path.is_symlink():
        raise SonarToolError("Sonar no genero recibo nuevo report-task.txt.")
    for line in path.read_text().splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key in values:
            raise SonarToolError("Sonar: recibo con campos duplicados.")
        values[key] = value
    if (values.get("projectKey") != project or values.get("serverUrl", "").rstrip("/") != base
            or not values.get("ceTaskId")):
        raise SonarToolError("Sonar: recibo ajeno o incompleto.")
    return values

def verify_task(task: dict, task_id: str, project: str) -> None:
    if not isinstance(task, dict) or task.get("id") != task_id or task.get("componentKey") != project:
        raise SonarToolError("Sonar: CE task/proyecto ajeno.")
    if task.get("status") == "SUCCESS" and not task.get("analysisId"):
        raise SonarToolError("Sonar: CE SUCCESS sin analysisId.")

def verify_latest(request: Callable, base: str, token: str, project: str, analysis: str) -> None:
    payload = request(base, token, "/api/project_analyses/search", {"project": project, "ps": 1, "p": 1})
    analyses = payload.get("analyses")
    if not isinstance(analyses, list) or not analyses or not isinstance(analyses[0], dict) or analyses[0].get("key") != analysis:
        raise SonarToolError("Sonar: el ultimo analisis no coincide con el recibo; reporte rechazado.")
