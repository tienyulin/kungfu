FROM mcr.microsoft.com/devcontainers/python:3.14

# Install the dev toolchain at IMAGE BUILD time (not postCreate) so the
# environment is baked into the image, cached, and identical everywhere.
# Build context is the repo root (see devcontainer.json "context": "..").
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt
