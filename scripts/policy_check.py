import sys
import yaml

if len(sys.argv) != 2:
    print(f"Usage: {sys.argv[0]} <manifest.yaml>", file=sys.stderr)
    sys.exit(2)

path = sys.argv[1]

try:
    with open(path) as f:
        manifest = yaml.safe_load(f)
except FileNotFoundError:
    print(f"ERROR: {path} not found", file=sys.stderr)
    sys.exit(2)
except yaml.YAMLError as e:
    print(f"ERROR: invalid YAML in {path}: {e}", file=sys.stderr)
    sys.exit(2)

failures = 0

for container in manifest["containers"]:
    name = container["name"]
    image = container["image"]
    run_as_non_root = container.get("runAsNonRoot")

    if image.endswith(":latest"):
        print(f"FAIL: {name} uses :latest tag")
        failures += 1

    if run_as_non_root is not True:
        print(f"FAIL: {name} may run as root")
        failures += 1

if failures > 0:
    print(f"\n{failures} check(s) failed")
    sys.exit(1)

print("All checks passed")
