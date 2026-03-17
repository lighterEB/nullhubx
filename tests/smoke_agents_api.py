#!/usr/bin/env python3
import json
import sys
import urllib.error
import urllib.request


def request_json(base_url: str, method: str, path: str, payload=None):
    url = f"{base_url}{path}"
    data = None
    headers = {"Accept": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            status = resp.status
            body = resp.read().decode("utf-8")
    except urllib.error.HTTPError as err:
        status = err.code
        body = err.read().decode("utf-8")

    parsed = None
    if body:
        try:
            parsed = json.loads(body)
        except json.JSONDecodeError:
            parsed = {"_raw": body}
    return status, parsed


def expect(status: int, allowed, label: str):
    if status not in allowed:
        raise RuntimeError(f"{label} failed: status={status}, expected one of {allowed}")


def pick_instance(status_json):
    instances = status_json.get("instances", {})
    for component, names in instances.items():
        if isinstance(names, dict) and names:
            first_name = next(iter(names.keys()))
            return component, first_name
    raise RuntimeError("No instance found in /api/status; cannot run agents smoke test")


def main():
    base_url = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:19810"

    health_status, health_json = request_json(base_url, "GET", "/health")
    expect(health_status, {200}, "health")
    if not isinstance(health_json, dict) or health_json.get("status") != "ok":
        raise RuntimeError("health response is not {'status':'ok'}")

    status_code, status_json = request_json(base_url, "GET", "/api/status")
    expect(status_code, {200}, "status")
    if not isinstance(status_json, dict):
        raise RuntimeError("status response is not valid JSON object")

    component, name = pick_instance(status_json)
    print(f"[smoke] target instance: {component}/{name}")

    profiles_path = f"/api/instances/{component}/{name}/agents/profiles"
    bindings_path = f"/api/instances/{component}/{name}/agents/bindings"

    get_profiles_status, original_profiles = request_json(base_url, "GET", profiles_path)
    expect(get_profiles_status, {200}, "get profiles")
    get_bindings_status, original_bindings = request_json(base_url, "GET", bindings_path)
    expect(get_bindings_status, {200}, "get bindings")

    if not isinstance(original_profiles, dict) or "profiles" not in original_profiles:
        raise RuntimeError("profiles GET payload shape is invalid")
    if not isinstance(original_bindings, dict) or "bindings" not in original_bindings:
        raise RuntimeError("bindings GET payload shape is invalid")

    def restore():
        put_profiles_status, _ = request_json(base_url, "PUT", profiles_path, original_profiles)
        expect(put_profiles_status, {200}, "restore profiles")
        put_bindings_status, _ = request_json(base_url, "PUT", bindings_path, original_bindings)
        expect(put_bindings_status, {200}, "restore bindings")

    try:
        roundtrip_profiles_status, _ = request_json(base_url, "PUT", profiles_path, original_profiles)
        expect(roundtrip_profiles_status, {200}, "profiles roundtrip PUT")

        roundtrip_bindings_status, _ = request_json(base_url, "PUT", bindings_path, original_bindings)
        expect(roundtrip_bindings_status, {200}, "bindings roundtrip PUT")

        invalid_profiles = {
            "defaults": {"model_primary": "not-valid"},
            "profiles": [],
        }
        invalid_profiles_status, _ = request_json(base_url, "PUT", profiles_path, invalid_profiles)
        expect(invalid_profiles_status, {400}, "invalid defaults.model_primary")

        invalid_bindings = {
            "bindings": [
                {
                    "agent_id": "__missing_profile__",
                    "match": {
                        "channel": "telegram",
                        "peer": {"kind": "topic", "id": "123"},
                    },
                }
            ]
        }
        invalid_bindings_status, _ = request_json(base_url, "PUT", bindings_path, invalid_bindings)
        expect(invalid_bindings_status, {400}, "invalid binding agent_id")

        normalization_payload = {
            "bindings": [
                {
                    "agent_id": "main",
                    "match": {
                        "channel": "telegram",
                        "account_id": "default",
                        "peer": {"kind": "topic", "id": "5314812038#topic:42"},
                    },
                }
            ]
        }
        normalize_put_status, _ = request_json(base_url, "PUT", bindings_path, normalization_payload)
        expect(normalize_put_status, {200}, "bindings normalization PUT")

        normalize_get_status, normalized = request_json(base_url, "GET", bindings_path)
        expect(normalize_get_status, {200}, "bindings normalization GET")
        bindings = normalized.get("bindings", []) if isinstance(normalized, dict) else []
        if not bindings:
            raise RuntimeError("normalized bindings list is empty")
        peer_id = (
            bindings[0]
            .get("match", {})
            .get("peer", {})
            .get("id", "")
        )
        if peer_id != "5314812038:thread:42":
            raise RuntimeError(f"topic id was not normalized, got: {peer_id!r}")
    finally:
        restore()

    print("[smoke] agents API smoke passed")


if __name__ == "__main__":
    main()
