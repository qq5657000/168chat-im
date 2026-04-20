#!/usr/bin/env python3
"""
Codemagic: locate uploaded .mobileprovision for BUNDLE_ID, write export_options.plist,
print shell exports for PROFILE_NAME and TEAM_ID (eval in bash).
"""
from __future__ import annotations

import glob
import os
import plistlib
import shlex
import subprocess
import sys


def _main() -> int:
    bundle = os.environ.get("BUNDLE_ID", "").strip()
    if not bundle:
        print("BUNDLE_ID is not set.", file=sys.stderr)
        return 1

    profile_dir = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")
    paths = sorted(glob.glob(os.path.join(profile_dir, "*.mobileprovision")))
    if not paths:
        print(
            f"No .mobileprovision files under {profile_dir}. "
            "Upload a provisioning profile in the workflow Code signing identities.",
            file=sys.stderr,
        )
        return 1

    chosen: dict | None = None
    for path in paths:
        try:
            raw = subprocess.check_output(
                ["security", "cms", "-D", "-i", path],
                stderr=subprocess.DEVNULL,
            )
            data = plistlib.loads(raw)
        except Exception:
            continue
        ent = data.get("Entitlements") or {}
        aid = ent.get("application-identifier") or ""
        if isinstance(aid, list):
            aid = aid[0] if aid else ""
        if aid.endswith("." + bundle) or aid == bundle:
            chosen = data
            break

    if not chosen:
        print(
            f"No provisioning profile matching bundle id {bundle!r} under {profile_dir}.",
            file=sys.stderr,
        )
        return 1

    name = chosen.get("Name") or ""
    team_ids = chosen.get("TeamIdentifier") or []
    team_id = ""
    if isinstance(team_ids, list) and team_ids:
        team_id = str(team_ids[0])
    if not team_id:
        team_id = (os.environ.get("IOS_TEAM_ID") or "").strip()
    if not team_id:
        print(
            "Could not read TeamIdentifier from the profile; set IOS_TEAM_ID in Codemagic.",
            file=sys.stderr,
        )
        return 1

    out_path = "/Users/builder/export_options.plist"
    export_opts: dict = {
        "method": "app-store",
        "signingStyle": "manual",
        "teamID": team_id,
        "provisioningProfiles": {bundle: name},
    }
    with open(out_path, "wb") as fh:
        plistlib.dump(export_opts, fh)

    print(
        f"Wrote {out_path} (profile name={name!r}, teamID={team_id!r}, bundle={bundle!r})",
        file=sys.stderr,
    )
    print(f"export PROFILE_NAME={shlex.quote(name)}")
    print(f"export TEAM_ID={shlex.quote(team_id)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
