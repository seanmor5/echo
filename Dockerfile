ARG ELIXIR_VERSION=1.15.0
ARG OTP_VERSION=26.0.2
ARG DEBIAN_VERSION=bullseye-20230612-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM rust as rust

FROM ${BUILDER_IMAGE} as builder
COPY --from=rust /usr/local/cargo /usr/local/cargo
ENV PATH=$PATH:/usr/local/cargo/bin
# install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git wget \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"
ENV BUMBLEBEE_CACHE_DIR="/app/.bumblebee"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN rustup default stable && mix deps.compile

COPY priv priv

COPY lib lib

# Compile the release
RUN  mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

ENV ELEVEN_LABS_MODEL_ID="eleven_turbo_v2"
ENV ELEVEN_LABS_VOICE_ID="21m00Tcm4TlvDq8ikWAM"
ENV ELEVEN_LABS_OPTIMIZE_STREAMING_LATENCY=2
ENV ELEVEN_LABS_OUTPUT_FORMAT="mp3_22050_32"

RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

EXPOSE 4000

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"
ENV BUMBLEBEE_CACHE_DIR="/app/.bumblebee"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/echo ./

USER nobody

CMD ["/app/bin/server"]
