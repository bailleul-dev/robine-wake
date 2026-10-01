# Robine Wake demo: the real server with emulated hardware, on one port.
# The product app (priv/web, built by `make expo-web`) and the 3D room are
# served side by side at /demo. See README "Demo mode".
#
#   docker build -t robine-wake-demo .
#   docker run -p 8080:8080 -e ROBINE_DEMO_ACCESS_CODE=... -v robine-demo:/app/data robine-wake-demo
#
# The runtime image must use the same Debian release as the builder (the
# release ships the builder's ERTS).

ARG BUILDER_IMAGE=elixir:1.20.2-otp-29
ARG RUNTIME_IMAGE=debian:trixie-slim

FROM ${BUILDER_IMAGE} AS build

RUN apt-get update && apt-get install -y --no-install-recommends build-essential git ca-certificates \
  && rm -rf /var/lib/apt/lists/*

ENV MIX_ENV=prod MIX_TARGET=host
WORKDIR /src

RUN mix local.hex --force && mix local.rebar --force && mix archive.install hex nerves_bootstrap --force

COPY mix.exs mix.lock ./
COPY nerves_system_rpi3/mix.exs nerves_system_rpi3/mix.exs
COPY config config
RUN mix deps.get --only prod && mix deps.compile

COPY lib lib
COPY lib_host lib_host
COPY priv priv
COPY rel rel
RUN mix release robine_wake_demo

FROM ${RUNTIME_IMAGE}

RUN apt-get update && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    ROBINE_DEMO=1 PORT=8080 ROBINE_ROOM_DIR=/app/room

WORKDIR /app
RUN useradd --system --home /app robine && mkdir -p /app/data /app/tmp && chown -R robine /app

COPY --from=build --chown=robine /src/_build/prod/rel/robine_wake_demo ./
COPY --chown=robine hardware/robine_enclosure/soundbar/viewer room

USER robine
VOLUME /app/data
EXPOSE 8080
CMD ["/app/bin/robine_wake_demo", "start"]
