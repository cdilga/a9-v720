# syntax=docker/dockerfile:1
#
# a9-v720 fake server (STA mode) — packaged image.
# Built and published by CI (.github/workflows/docker-publish.yml) to
# ghcr.io/cdilga/a9-v720. Deployments PULL an immutable tag; nothing is built
# on the deploy host.
#
# ── HARD CONSTRAINT: Python must be <= 3.11 ──────────────────────────────────
# The source calls Thread.setDaemon()/setName() (removed in CPython 3.12).
# Do NOT bump past 3.11 or the fake server crashes on the first thread spawn.
FROM python:3.11-slim-bookworm

WORKDIR /app

# numpy/opencv/netifaces: netifaces has no guaranteed cp311 manylinux wheel, so a
# C toolchain is needed at build time (purged after). opencv-python dlopens libGL
# at import; the -s fake-server path never touches cv2's GUI, so we swap in
# opencv-python-headless and avoid the whole libGL/libglib runtime.
COPY requirements.txt ./
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends build-essential; \
    sed -i 's/^opencv-python==/opencv-python-headless==/' requirements.txt; \
    pip install --no-cache-dir -r requirements.txt; \
    apt-get purge -y build-essential; \
    apt-get autoremove -y; \
    rm -rf /var/lib/apt/lists/*

# The HTTP handler serves static/ relative to CWD, so CWD must stay /app.
COPY src/ ./src/
COPY static/ ./static/

# 80/tcp   — bootstrap REST (registerDevices, confirm, getA9ConfCheck) + MJPEG out
# 6123/tcp — device registration + JSON command/control channel
# 6123/udp — NAT-probe + JPEG (P2P_UDP_CMD_JPEG) / G711 / PCM data channel
EXPOSE 80/tcp 6123/tcp 6123/udp

# -s = start the fake server in the foreground; the container is the process.
CMD ["python3", "src/a9_naxclow.py", "-s"]
