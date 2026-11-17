#!/usr/bin/env python3
"""Answers two questions for the workflows, from the pipeline config given as JSON:

  validate CONFIG                     is the config usable?
  plan CONFIG --environment ENV ...   which sites does this push publish?

The workflows turn .github/pipeline.yml into JSON first, so this file needs nothing
beyond the Python standard library.
"""
import argparse
import json
import os
import re
import subprocess
import sys

SITE_NAME = re.compile(r"^[a-z0-9][a-z0-9-]*$")
ENVIRONMENTS = ("production", "staging")
NO_COMMIT = "0" * 40
TARGETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "targets")


def target_types():
    return sorted(name[:-3] for name in os.listdir(TARGETS) if name.endswith(".sh"))


def problems(config, root):
    """Every reason the config can't be used, as plain sentences."""
    if not isinstance(config, dict) or not isinstance(config.get("sites"), list) or not config["sites"]:
        return ["The config needs a 'sites' list with at least one site."]

    found, seen, types = [], set(), target_types()
    for position, site in enumerate(config["sites"], 1):
        if not isinstance(site, dict):
            found.append(f"Site {position} must be a block with name, path and production.")
            continue
        name = site.get("name")
        label = f"Site '{name}'" if isinstance(name, str) else f"Site {position}"

        if not isinstance(name, str) or not SITE_NAME.match(name):
            found.append(f"{label}: 'name' must use lowercase letters, numbers and dashes.")
        elif name in seen:
            found.append(f"{label}: the name is used twice.")
        seen.add(name if isinstance(name, str) else None)

        path = site.get("path")
        if not isinstance(path, str) or not path.strip():
            found.append(f"{label}: 'path' is missing.")
        elif os.path.isabs(path) or ".." in path.replace("\\", "/").split("/"):
            found.append(f"{label}: 'path' must stay inside the repository.")
        elif not os.path.isdir(os.path.join(root, path)):
            found.append(f"{label}: the folder '{path}' doesn't exist.")

        if "production" not in site:
            found.append(f"{label}: 'production' is missing.")
        for environment in ENVIRONMENTS:
            if environment not in site:
                continue
            target = site[environment]
            kind = target.get("type") if isinstance(target, dict) else None
            if kind not in types:
                found.append(
                    f"{label}: {environment} 'type' must be one of: {', '.join(types)}."
                )
    return found


def changed(before, after, path):
    """Whether anything under path differs between the two commits."""
    if not before or before == NO_COMMIT:
        return True
    result = subprocess.run(["git", "diff", "--quiet", before, after, "--", path])
    if result.returncode in (0, 1):
        return result.returncode == 1
    # The earlier commit is unknown here (a force push, for example), so publish.
    print(f"Couldn't compare {before} with {after}; publishing '{path}'.", file=sys.stderr)
    return True


def plan(config, environment, before, after, only):
    sites = [site for site in config["sites"] if environment in site]
    if only:
        sites = [site for site in sites if site["name"] == only]
        if not sites:
            sys.exit(f"No site named '{only}' has a {environment} target.")
    else:
        sites = [site for site in sites if changed(before, after, site["path"])]
    return [
        {
            "name": site["name"],
            "path": site["path"],
            "type": site[environment]["type"],
            "target": {k: v for k, v in site[environment].items() if k != "type"},
        }
        for site in sites
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    check = commands.add_parser("validate")
    check.add_argument("config")

    planner = commands.add_parser("plan")
    planner.add_argument("config")
    planner.add_argument("--environment", required=True, choices=ENVIRONMENTS)
    planner.add_argument("--before", default="")
    planner.add_argument("--after", default="HEAD")
    planner.add_argument("--site", default="", help="publish this site whether or not it changed")

    args = parser.parse_args()
    with open(args.config, encoding="utf-8") as handle:
        config = json.load(handle)

    found = problems(config, os.getcwd())
    if found:
        print("The pipeline config has problems:", file=sys.stderr)
        for problem in found:
            print(f"  - {problem}", file=sys.stderr)
        sys.exit(1)

    if args.command == "validate":
        print(f"Pipeline config is valid: {len(config['sites'])} site(s).")
    else:
        print(json.dumps(plan(config, args.environment, args.before, args.after, args.site), separators=(",", ":")))


if __name__ == "__main__":
    main()
