from pathlib import Path


def main() -> None:
    # Resolve the path from this script's location so it works from any working directory.
    project_root = Path(__file__).resolve().parent.parent
    out_path = project_root / "runs" / "output.txt"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    # Write exactly "pipeline ok" with no trailing newline.
    out_path.write_text("pipeline ok", encoding="utf-8", newline="")


if __name__ == "__main__":
    main()
