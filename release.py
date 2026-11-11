#!/usr/bin/env python3
"""Build, test and package CowCasino for both clients in one pass.

    python3 release.py              check, test on both clients, write CowCasino.zip
    python3 release.py --no-zip     check and test only

One folder serves both clients:
  CowCasino.toc           read by the 1.12 client (Octo / Turtle), loads Compat112.lua
  CowCasino_Mainline.toc  read by WoW Forever (the 1.12 client ignores it), loads CompatModern.lua
CowCasino.toc is the one to edit; this script writes CowCasino_Mainline.toc from it.
"""
import os, re, subprocess, sys, zipfile
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(HERE, "CowCasino")
TESTS = os.path.join(HERE, "tests")
ZIP = os.path.join(HERE, "CowCasino.zip")
# A real saved-variables file (WTF\Account\...\SavedVariables\CowCasino.lua) for
# startup_tests; that test is skipped when there isn't one.
SAVED = os.environ.get("COWCASINO_SAVE", "/mnt/user-data/uploads/SavedVariables/CowCasino.lua")
COMPAT = {"Compat112.lua", "CompatModern.lua"}

MAINLINE_HEADER = """## Interface: 16001
## Title: |cffffd100CowCasino|r
## Notes: A just-for-fun casino. No real gold is ever wagered. Type /casino to open.
## Author: ruin9k
## Version: {version}
## IconTexture: Interface\\Icons\\INV_Misc_Coin_02
## AddonCompartmentFunc: CowCasino_OnAddonCompartmentClick
## SavedVariables: CowCasinoDB

"""

# Client-specific calls the shared game code must make through ns (see Compat112.lua).
FORBIDDEN = [
    r'(?<![\w.])CreateFrame\(', r'(?<![\w.])PlaySound\(', r'(?<![\w.])SendAddonMessage\(',
    r'(?<![\w.])GetNumPartyMembers', r'(?<![\w.])GetNumRaidMembers', r'(?<![\w.])getglobal\(',
    r'table\.getn', r'math\.mod\(', r'string\.gfind', r'string\.gmatch', r'\.mdx"', r'\.m2"',
]

TESTS_BOTH = ["harness112", "roulette_tests", "sound_tests", "options_tests", "merge_tests", "party_tests",
              "bj_party_tests", "slots_lines_tests", "rebuy_tests", "slots_machine_tests", "blinds_tests",
              "chat_tests", "whole_chips_tests", "portrait_tests", "tauren_cards_tests", "split_tests",
              "race_cards_tests", "bj_layout_tests", "startup_tests", "craps_tests", "party_craps_tests",
              "plinko_crash_tests", "slots_features_tests"]
TESTS_FOREVER_ONLY = ["net_throttle_tests"]


def fail(msg):
    print("FAILED: " + msg)
    sys.exit(1)


def lua_files():
    for root, _, files in os.walk(ADDON):
        for name in sorted(files):
            if name.endswith(".lua"):
                yield os.path.relpath(os.path.join(root, name), ADDON)


def write_mainline_toc():
    lines = open(os.path.join(ADDON, "CowCasino.toc"), encoding="utf-8").read().split("\n")
    version, files = None, []
    for line in lines:
        line = line.strip()
        if line.startswith("## Version:"):
            version = line.split(":", 1)[1].strip()
        elif line and not line.startswith("##"):
            files.append("CompatModern.lua" if line == "Compat112.lua" else line)
    if not version or files[0] != "CompatModern.lua":
        fail("CowCasino.toc needs a Version and Compat112.lua as its first file")
    for f in files:
        if not os.path.exists(os.path.join(ADDON, f.replace("\\", "/"))):
            fail("CowCasino.toc lists a missing file: " + f)
    with open(os.path.join(ADDON, "CowCasino_Mainline.toc"), "w", encoding="utf-8", newline="\n") as out:
        out.write(MAINLINE_HEADER.format(version=version) + "\n".join(files) + "\n")
    return version, len(files)


def static_checks():
    problems = []
    for rel in lua_files():
        if rel in COMPAT:
            continue
        for i, line in enumerate(open(os.path.join(ADDON, rel), encoding="utf-8"), 1):
            code = line.split("--", 1)[0]
            for f in FORBIDDEN:
                if re.search(f, code):
                    problems.append(f"{rel}:{i}: client-specific call, use ns: {line.strip()}")
    for rel in lua_files():
        path = os.path.join(ADDON, rel)
        if rel != "CompatModern.lua":           # everything else runs on Lua 5.0 too
            out = subprocess.run([sys.executable, os.path.join(TESTS, "lua50check.py"), path],
                                 capture_output=True, text=True).stdout.strip().split("\n")
            if out[-1] != "0 problems":
                problems.append(f"{rel}: Lua 5.0: " + "; ".join(out))
            listing = subprocess.run(["texluac", "-p", "-l", "-l", path], capture_output=True, text=True)
            if listing.returncode:
                problems.append(f"{rel}: {listing.stderr.strip()}")
            for m in re.finditer(r"^upvalues \((\d+)\)", listing.stdout, re.M):
                if int(m.group(1)) > 32:        # Lua 5.0 allows 32 (texluac also counts _ENV)
                    problems.append(f"{rel}: a function has {m.group(1)} upvalues (1.12 allows 32)")
    if problems:
        fail("static checks\n  " + "\n  ".join(problems))


def run_test(name, mock):
    args = ["texlua", name + ".lua", ADDON] + ([SAVED] if name == "startup_tests" else [])
    env = dict(os.environ)
    if mock:
        env["MOCK"] = mock
    else:
        env.pop("MOCK", None)
    r = subprocess.run(args, cwd=TESTS, env=env, capture_output=True, text=True, timeout=900)
    lines = (r.stdout + r.stderr).strip().split("\n")
    # every check must pass, not just the summary on the last line
    passed = r.returncode == 0 and "PASS" in lines[-1] and not any(re.search(r"\bFAIL\b", l) for l in lines)
    return name, ("Forever" if mock else "1.12"), passed, lines


def run_tests():
    subprocess.run([sys.executable, "make_mockretail.py"], cwd=TESTS, check=True)
    both = [t for t in TESTS_BOTH if t != "startup_tests" or os.path.exists(SAVED)]
    if len(both) < len(TESTS_BOTH):
        print("  (startup_tests skipped: set COWCASINO_SAVE to a CowCasino.lua saved-variables file to run it)")
    jobs = [(t, None) for t in both] + [(t, "mockretail.lua") for t in both + TESTS_FOREVER_ONLY]
    failed = []
    with ThreadPoolExecutor(max_workers=max(2, os.cpu_count() or 2)) as pool:
        for name, client, passed, lines in pool.map(lambda j: run_test(*j), jobs):
            print(f"  {client:8} {name:22} {'pass' if passed else 'FAIL'}")
            if not passed:
                failed.append((client, name, lines))
    for client, name, lines in failed:
        print(f"\n--- {client} {name} ---")
        print("\n".join(l for l in lines if "FAIL" in l or "rror" in l or "traceback" in l.lower())[-3000:] or "\n".join(lines[-20:]))
    if failed:
        fail(f"{len(failed)} test run(s)")
    return len(jobs)


def package():
    if os.path.exists(ZIP):
        os.remove(ZIP)
    with zipfile.ZipFile(ZIP, "w", zipfile.ZIP_DEFLATED) as z:
        for root, _, files in os.walk(ADDON):
            for name in sorted(files):
                path = os.path.join(root, name)
                z.write(path, os.path.join("CowCasino", os.path.relpath(path, ADDON)))


if __name__ == "__main__":
    version, nfiles = write_mainline_toc()
    print(f"CowCasino {version}: CowCasino_Mainline.toc written ({nfiles} files)")
    static_checks()
    print("static checks pass (shared calls, Lua 5.0, upvalues)")
    n = run_tests()
    print(f"all {n} test runs pass")
    if "--no-zip" not in sys.argv:
        package()
        print("wrote " + ZIP)
