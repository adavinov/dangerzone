import argparse
import gzip
import os
import platform
import subprocess
import sys
from pathlib import Path

BUILD_CONTEXT = "dangerzone/"
TAG = "dangerzone.rocks/dangerzone:latest"
REQUIREMENTS_TXT = "container-pip-requirements.txt"
if platform.system() in ["Darwin", "Windows"]:
    CONTAINER_RUNTIME = "docker"
elif platform.system() == "Linux":
    CONTAINER_RUNTIME = "podman"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--runtime",
        choices=["docker", "podman"],
        default=CONTAINER_RUNTIME,
        help=f"The container runtime for building the image (default: {CONTAINER_RUNTIME})",
    )
    parser.add_argument(
        "--no-save",
        action="store_true",
        help="Do not save the container image as a tarball in share/container.tar.gz",
    )
    parser.add_argument(
        "--compress-level",
        type=int,
        choices=range(0, 10),
        default=9,
        help="The Gzip compression level, from 0 (lowest) to 9 (highest, default)",
    )
    args = parser.parse_args()

    print("Exporting container pip dependencies")
    with ContainerPipDependencies():
        print("Pulling base image")
        subprocess.run(
            [
                args.runtime,
                "pull",
                "alpine:latest",
            ],
            check=True,
        )

        print("Building container image")
        subprocess.run(
            [
                args.runtime,
                "build",
                BUILD_CONTEXT,
                "--build-arg",
                f"REQUIREMENTS_TXT={REQUIREMENTS_TXT}",
                "-f",
                "Dockerfile",
                "--tag",
                TAG,
            ],
            check=True,
        )

        if not args.no_save:
            print("Saving container image")
            cmd = subprocess.Popen(
                [
                    CONTAINER_RUNTIME,
                    "save",
                    TAG,
                ],
                stdout=subprocess.PIPE,
            )

            print("Compressing container image")
            chunk_size = 4 << 20
            with gzip.open(
                "share/container.tar.gz",
                "wb",
                compresslevel=args.compress_level,
            ) as gzip_f:
                while True:
                    chunk = cmd.stdout.read(chunk_size)
                    if len(chunk) > 0:
                        gzip_f.write(chunk)
                    else:
                        break
            cmd.wait(5)

    print("Looking up the image id")
    image_id = subprocess.check_output(
        [
            args.runtime,
            "image",
            "list",
            "--format",
            "{{.ID}}",
            TAG,
        ],
        text=True,
    )
    with open("share/image-id.txt", "w") as f:
        f.write(image_id)


class ContainerPipDependencies:
    """Generates PIP dependencies within container"""

    def __enter__(self):
        try:
            container_requirements_txt = subprocess.check_output(
                ["poetry", "export", "--only", "container"], universal_newlines=True
            )
        except subprocess.CalledProcessError as e:
            print("FAILURE", e.returncode, e.output)
        print(f"REQUIREMENTS: {container_requirements_txt}")
        with open(Path(BUILD_CONTEXT) / REQUIREMENTS_TXT, "w") as f:
            f.write(container_requirements_txt)

    def __exit__(self, exc_type, exc_value, exc_tb):
        print("Leaving the context...")
        os.remove(Path(BUILD_CONTEXT) / REQUIREMENTS_TXT)


if __name__ == "__main__":
    sys.exit(main())
