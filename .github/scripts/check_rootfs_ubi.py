#!/usr/bin/env python3
import argparse
import json
import os
import shutil
import stat
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, List, Tuple, Optional

REQUIRED_CHECKS = [
    # Any of these paths satisfy the check (OR groups)
    ("udevadm_present", [["bin/udevadm"], ["sbin/udevadm"]]),
    ("udev_rules_or_etc", [["etc/udev"], ["lib/udev/rules.d"]]),
    ("libkmod_present", [
        ["lib/libkmod.so"],
        ["lib/libkmod.so.2"],
        ["lib/libkmod.so.2.3.7"],
        ["lib32/libkmod.so"],
        ["lib32/libkmod.so.2"],
        ["lib64/libkmod.so"],
        ["lib64/libkmod.so.2"],
    ]),
    ("libblkid_present", [
        ["lib/libblkid.so"],
        ["lib32/libblkid.so"],
        ["lib64/libblkid.so"],
    ]),
    ("init_script_S10udev", [["etc/init.d/S10udev"]]),
    ("sbin_init_executable", [["sbin/init"]]),
    ("busybox_executable", [["bin/busybox"], ["usr/bin/busybox"], ["sbin/busybox"]]),
]

OPTIONAL_PRESENCE = [
    "etc/init.d/S50usbdevice",
    "etc/init.d/S99_auto_reboot",
    "linuxrc",
    "rockchip_test",
]

KEY_CONFIG_GREP = [
    "BR2_PACKAGE_EUDEV",
    "BR2_PACKAGE_KMOD",
    "BR2_PACKAGE_UTIL_LINUX",
    "BR2_PACKAGE_UTIL_LINUX_LIBBLKID",
    "BR2_PACKAGE_BUSYBOX",
    "BR2_ROOTFS_OVERLAY",
]

def run_cmd(cmd: List[str], cwd: Optional[Path], log_fp) -> int:
    log_fp.write(f"\n$ {' '.join(cmd)}\n")
    log_fp.flush()
    p = subprocess.Popen(
        cmd,
        cwd=str(cwd) if cwd else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert p.stdout is not None
    for line in p.stdout:
        log_fp.write(line)
    return p.wait()

def sha256sum(path: Path) -> str:
    import hashlib
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def is_executable(path: Path) -> bool:
    try:
        st = path.stat()
    except FileNotFoundError:
        return False
    return bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))

def find_largest_file(root: Path) -> Optional[Path]:
    largest = None
    largest_size = -1
    for p in root.rglob("*"):
        if p.is_file():
            try:
                sz = p.stat().st_size
            except OSError:
                continue
            if sz > largest_size:
                largest = p
                largest_size = sz
    return largest

def check_any_paths(extracted_root: Path, path_groups: List[List[str]]) -> Tuple[bool, List[str]]:
    """
    path_groups: list of alternative path lists, where each alternative is a list of path components.
    Example: [["bin/udevadm"], ["sbin/udevadm"]]
    """
    hits = []
    for alt in path_groups:
        rel = alt[0]
        p = extracted_root / rel
        if p.exists():
            hits.append(rel)
    return (len(hits) > 0), hits

def collect_tree_snippets(extracted_root: Path) -> str:
    interesting_roots = [
        extracted_root / "etc",
        extracted_root / "lib",
        extracted_root / "lib32",
        extracted_root / "lib64",
        extracted_root / "bin",
        extracted_root / "sbin",
        extracted_root / "usr/bin",
    ]
    lines: List[str] = []
    for r in interesting_roots:
        if r.exists():
            lines.append(f"\n== TREE {r.relative_to(extracted_root)} ==\n")
            # Limit output for readability
            for p in sorted(r.rglob("*"))[:5000]:
                try:
                    rel = p.relative_to(extracted_root)
                except Exception:
                    rel = p
                if p.is_dir():
                    continue
                try:
                    sz = p.stat().st_size
                except OSError:
                    sz = -1
                lines.append(f"{sz:10d} {rel}")
    return "\n".join(lines) + "\n"

def find_buildroot_configs(search_root: Path) -> List[Path]:
    configs = []
    # Common patterns in buildroot output trees
    for pat in [
        "**/buildroot*/output*/.config",
        "**/buildroot*/output*/build/.config",
        "**/buildroot*/output*/buildroot/.config",
        "**/buildroot*/output*/buildroot-*/.config",
    ]:
        configs.extend(search_root.glob(pat))
    # De-dup
    uniq = []
    seen = set()
    for c in configs:
        rp = str(c.resolve())
        if rp not in seen and c.is_file():
            uniq.append(c)
            seen.add(rp)
    return uniq

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--rootfs-img", required=True, help="Path to rootfs.img (UBI image)")
    ap.add_argument("--outdir", required=True, help="Output directory for logs/extraction")
    ap.add_argument("--workspace", default=".", help="Workspace root for extra logging (default: .)")
    args = ap.parse_args()

    rootfs_img = Path(args.rootfs_img).resolve()
    outdir = Path(args.outdir).resolve()
    workspace = Path(args.workspace).resolve()

    outdir.mkdir(parents=True, exist_ok=True)

    log_path = outdir / "check.log"
    summary_path = outdir / "summary.txt"
    checks_path = outdir / "required_checks.json"
    snippets_path = outdir / "tree_snippets.txt"
    meta_path = outdir / "meta.json"

    workdir = outdir / f"work_{int(time.time())}"
    if workdir.exists():
        shutil.rmtree(workdir)
    workdir.mkdir(parents=True, exist_ok=True)

    with log_path.open("w", encoding="utf-8") as log_fp:
        log_fp.write("check_rootfs_ubi.py\n")
        log_fp.write(f"rootfs_img={rootfs_img}\n")
        log_fp.write(f"outdir={outdir}\n")
        log_fp.write(f"workdir={workdir}\n")
        log_fp.write(f"workspace={workspace}\n")

        if not rootfs_img.exists():
            log_fp.write(f"ERROR: rootfs image not found: {rootfs_img}\n")
            return 2

        # Record metadata
        meta = {
            "rootfs_img": str(rootfs_img),
            "rootfs_img_size": rootfs_img.stat().st_size,
            "rootfs_img_sha256": sha256sum(rootfs_img),
        }

        # Dump relevant env
        env_dump = {}
        for k, v in os.environ.items():
            if k == "BR2_EXTERNAL" or k.startswith("BR2_"):
                env_dump[k] = v
        meta["env"] = env_dump

        # Find buildroot configs and grep for key lines
        br_configs = find_buildroot_configs(workspace)
        meta["buildroot_configs"] = [str(p) for p in br_configs]

        config_hits: Dict[str, Dict[str, List[str]]] = {}
        for cfg in br_configs[:5]:  # avoid huge spam if many
            hits = {}
            try:
                txt = cfg.read_text(encoding="utf-8", errors="ignore").splitlines()
            except Exception as e:
                hits["__error__"] = [str(e)]
                config_hits[str(cfg)] = hits
                continue
            for key in KEY_CONFIG_GREP:
                matched = [line for line in txt if line.startswith(key + "=") or line.startswith("# " + key)]
                if matched:
                    hits[key] = matched[:20]
            config_hits[str(cfg)] = hits
        meta["buildroot_config_grep"] = config_hits

        # Run ubireader extract images
        # Copy rootfs into workdir to avoid ubireader creating odd nested paths in the source tree
        local_img = workdir / rootfs_img.name
        shutil.copy2(rootfs_img, local_img)

        rc = run_cmd(
            [sys.executable, "-m", "ubireader.scripts.ubireader_extract_images", str(local_img)],
            cwd=workdir,
            log_fp=log_fp,
        )
        if rc != 0:
            log_fp.write(f"ERROR: ubireader_extract_images failed rc={rc}\n")
            return 3

        ubifs_root = workdir / "ubifs-root"
        if not ubifs_root.exists():
            log_fp.write("ERROR: ubifs-root not found after extraction\n")
            return 4

        # ubireader may create a directory named after the input file; find largest file anywhere under ubifs-root
        vol_file = find_largest_file(ubifs_root)
        if vol_file is None:
            log_fp.write("ERROR: could not find extracted volume file under ubifs-root\n")
            return 5

        meta["volume_file"] = str(vol_file)
        meta["volume_file_size"] = vol_file.stat().st_size
        meta["volume_file_sha256"] = sha256sum(vol_file)

        extracted_rootfs = workdir / "extracted_rootfs"
        extracted_rootfs.mkdir(parents=True, exist_ok=True)

        rc = run_cmd(
            [sys.executable, "-m", "ubireader.scripts.ubireader_extract_files", str(vol_file), "-o", str(extracted_rootfs)],
            cwd=workdir,
            log_fp=log_fp,
        )
        if rc != 0:
            log_fp.write(f"ERROR: ubireader_extract_files failed rc={rc}\n")
            return 6

        # Some ubireader versions create nested dirs; try to locate the actual rootfs top
        # Heuristic: look for sbin/init or bin/busybox under extracted_rootfs
        candidates = [extracted_rootfs] + [p for p in extracted_rootfs.rglob("*") if p.is_dir()]
        root_candidate = None
        for c in candidates:
            if (c / "sbin/init").exists() or (c / "bin/busybox").exists() or (c / "usr/bin/busybox").exists():
                root_candidate = c
                break
        if root_candidate is None:
            root_candidate = extracted_rootfs

        meta["extracted_rootfs_dir"] = str(root_candidate)

        # Run required checks
        results = []
        failed = False

        for name, groups in REQUIRED_CHECKS:
            ok, hits = check_any_paths(root_candidate, groups)
            extra = {}
            if name == "sbin_init_executable":
                p = root_candidate / "sbin/init"
                extra["exists"] = p.exists()
                extra["executable"] = is_executable(p) if p.exists() else False
                ok = ok and extra["executable"]
            if name == "busybox_executable":
                # ensure at least one candidate is executable
                exec_ok = False
                exec_hits = []
                for alt in groups:
                    rel = alt[0]
                    p = root_candidate / rel
                    if p.exists():
                        exec_hits.append(rel)
                        if is_executable(p):
                            exec_ok = True
                extra["found"] = exec_hits
                extra["any_executable"] = exec_ok
                ok = exec_ok
                hits = exec_hits

            results.append({
                "check": name,
                "ok": ok,
                "hits": hits,
                "extra": extra,
            })
            if not ok:
                failed = True

        # Optional presence report
        optional = {}
        for rel in OPTIONAL_PRESENCE:
            optional[rel] = (root_candidate / rel).exists()

        meta["optional_presence"] = optional

        # Save snippets (to help debug diffs)
        snippets_path.write_text(collect_tree_snippets(root_candidate), encoding="utf-8", errors="ignore")

        # Save results
        checks_path.write_text(json.dumps({"results": results, "optional": optional}, indent=2), encoding="utf-8")

        # Write summary
        lines = []
        lines.append("Rootfs UBI sanity check summary")
        lines.append(f"rootfs_img: {rootfs_img}")
        lines.append(f"rootfs_img_sha256: {meta['rootfs_img_sha256']}")
        lines.append(f"volume_file: {meta['volume_file']}")
        lines.append(f"volume_file_sha256: {meta['volume_file_sha256']}")
        lines.append(f"extracted_rootfs_dir: {meta['extracted_rootfs_dir']}")
        lines.append("")
        for r in results:
            status = "OK" if r["ok"] else "FAIL"
            lines.append(f"[{status}] {r['check']} hits={r['hits']} extra={r.get('extra', {})}")
        lines.append("")
        lines.append("Optional presence:")
        for k, v in optional.items():
            lines.append(f"  {k}: {'present' if v else 'missing'}")
        lines.append("")
        if br_configs:
            lines.append("Buildroot .config grep (first few configs):")
            for cfg, hits in list(config_hits.items())[:5]:
                lines.append(f"  {cfg}:")
                if not hits:
                    lines.append("    (no matches)")
                else:
                    for key, vals in hits.items():
                        lines.append(f"    {key}: {vals}")
        summary_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

        meta_path.write_text(json.dumps(meta, indent=2), encoding="utf-8")

        log_fp.write("\n=== SUMMARY ===\n")
        log_fp.write(summary_path.read_text(encoding="utf-8", errors="ignore"))
        log_fp.write("\n=== END ===\n")

    if failed:
        print(f"ERROR: required rootfs components missing; see {summary_path} and {log_path}")
        return 10

    print(f"OK: rootfs sanity checks passed; reports in {outdir}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
