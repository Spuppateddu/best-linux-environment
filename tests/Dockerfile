# Two images from one file. `fresh`: a bare Ubuntu with a sudo user, the machine
# ./setup.sh meets on a first run. `tools`: fresh plus shellcheck, bats and jq.
FROM ubuntu:26.04 AS fresh
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8
RUN apt-get update \
 && apt-get install -y --no-install-recommends sudo lsb-release \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -s /bin/bash tester \
 && echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tester
USER tester
WORKDIR /home/tester

FROM fresh AS tools
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends shellcheck bats git jq \
 && rm -rf /var/lib/apt/lists/*
USER tester
