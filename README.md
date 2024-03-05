# Echo

> Give your agents a voice with Echo.

Echo is a WebSocket server for conversational agents with low latency and support for interrupts. You can read the [origin blog post here](https://seanmoriarity.com/2024/02/25/implementing-natural-conversational-agents-with-elixir/).

## Usage

### Development Server

Echo is an [Elixir Phoenix](https://www.phoenixframework.org/) application. You can run the server by installing Elixir and Phoenix, setting the [required environment variables](#configuration) and running:

```sh
mix phx.server
```

This will start a server running on port 4000 with a single endpoint: `ws://localhost:4000/conversation`. I highly recommend you run on a GPU-enabled machine and set `XLA_ENV=cuda120`. I can get very low latency, but only by running transcription on a GPU.

### Docker Deployment

Alternatively, you can build a Docker image from the included `Dockerfile`

#### Build

Using the format:

```sh
docker build -t TAG_NAME DOCKERFILE_PATH
```

Assuming you clone this repo and `cd` into the root of the repo (where the Dockerfile is):

```sh
docker build -t echo .
```

This will build a Docker image with the tag `echo`, but you can rename the tag or choose to not include any.

You can also pass any of the following as a `--build-arg`:

* `ELIXIR_VERSION` (defaults `1.15.0`)
* `OTP_VERSION` (defaults `26.0.2`)
* `DEBIAN_VERSION` (defaults `bullseye-20230612-slim`)
* `BUILDER_IMAGE` (defaults `hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}`)
* `RUNNER_IMAGE` (defaults `debian:${DEBIAN_VERSION}`)

You should not need to adjust the default values, but if you need to consult the Dockerfile itself for
information on their usage.

#### Run

Then to run the server do:

```sh
docker run \
  -e SECRET_KEY_BASE=$(mix phx.gen.secret) \
  -e OPENAI_API_KEY=YOUR_API_KEY \
  -e TEXT_GENERATION_MODEL=gpt-3.5-turbo \
  -e SPEECH_TO_TEXT_MODEL=distil-whisper/distil-medium.en \
  -e ELEVEN_LABS_API_KEY=YOUR_OTHER_API_KEY \
  -p 4001:4000 echo
```

The Dockerfile builds the server as a production release, so you'll need to include the `SECRET_KEY_BASE` string.
`mix phx.gen.secret` will generate a new secret for you, but you can use any secrey you desire.

`-p 4001:4000` binds your host's port 4001 to the containers port 4000. If you want to bind to a different port on
your host machine just change the first number, like `-p PORT:4000`.

You can also pass any other environment variables accepted by the server, as described in detail below.

### Interacting with the WebSocket Server

> WARNING: This API is **extremely** alpha. I know it's kind of confusing, sorry.

The WebSocket server uses [MessagePack](https://msgpack.org/index.html) for serialization. Each message object contains a `type` field representing the type of message to send, and then some additional data. These are the types of messages you can send to the client:

* `{type: "open", prompt: "System prompt for agent"}`
* `{type: "audio", audio: ArrayBuffer}`
* `{type: "state", state: "waiting"}`

After connecting, you should send an "open" message to the server with the system prompt for the agent you'd like to interact with. The server will immediately start pushing audio. The types of messages the server sends to the client are:

* `{type: "audio", audio: ArrayBuffer}`
* `{type: "token", token: String}`
* `{type: "interrupt", token: String}`

Each audio event sends data as a MessagePack binary which will get decoded as a UInt8Array. The first 8 bytes are a sequencing token for interrupts. You should use the sequencing token to avoid race conditions in the event your agent is interrupted in the middle of streaming audio from ElevenLabs. The rest of the audio is a buffer matching the format provided in your configuration. For example, I recommend using `pcm_44100` which will output 16-bit PCM audio data. Then you can convert the incoming audio data like:

```js
const data = decoded.audio;

const tokenBytes = data.slice(0, 8);
const textDecoder = new TextDecoder("utf-8");
const token = textDecoder.decode(tokenBytes);

const audio = new Int16Array(data.buffer, data.byteOffset + 8, (data.byteLength - 8) / Int16Array.BYTES_PER_ELEMENT);
this.enqueueAudioData({ token, audio });
```

Assuming you're using a queue to sequence incoming audio events.

`interrupt` events tell you that your model has been interrupted while speaking, and you should stop playback. Each interrupt event creates a new sequencing token to avoid race conditions. `token` events update the sequencing token for audio playback.

You should send data to the server in the same endianness as the server. You should also send it as FP32 PCM data. I recommend streaming to the server in chunks between 30ms and 250ms. You *must* sample audio at 16_000 Hz. The VAD model requires audio sampled at 16_000 hurts to work well. It does not support samples smaller than 30ms. Here's an example which pushes every 128ms:

```js
    const audioOptions = {
      sampleRate: SAMPLING_RATE,
      echoCancellation: true,
      noiseSuppression: true,
      autoGainControl: true,
      channelCount: 1,
    };

    navigator.mediaDevices.getUserMedia({ audio: audioOptions }).then((stream) => {
      const source = this.microphoneContext.createMediaStreamSource(stream);
      this.processor = this.microphoneContext.createScriptProcessor(2048, 1, 1);

      this.processor.onaudioprocess = (e) => {
        const pcmFloat32Data = this.convertEndianness32(
          e.inputBuffer.getChannelData(0),
          this.getEndianness(),
          this.el.dataset.endianness
        );

        const message = { type: "audio", audio: pcmFloat32Data };

        this.socket.send(encoder.encode(message), { type: "application/octet-stream" });
      };

      source.connect(this.processor);
      this.processor.connect(this.microphoneContext.destination);
    });
```

## Configuration {#configuration}

Echo aims to be as configurable as possible. Right now you can configure each piece to varying extents.

### LLM Configuration

Echo supports configurable LLMs through environment variables. First, you must set a provider with `TEXT_GENERATION_PROVIDER`. There are 3 possible providers:

* `bumblebee` - Use a [Bumblebee](https://github.com/elixir-nx/bumblebee) supported model. This will run the model under an [Nx Serving](https://hexdocs.pm/nx/Nx.Serving.html) and has the benefit of no HTTP Request overhead. Models will be compiled with [XLA](https://github.com/openxla/xla).
* `openai` - Use an OpenAI model such as GPT-3.5 or GPT-4.
* `generic` - Use a generic model provider with an OpenAI compatible `/v1/chat/completions` endpoint.

Each provider has it's own specific configuration options. Some options are shared between providers.

#### Bumblebee Configuration

* `TEXT_GENERATION_MODEL` (required) - The HuggingFace model repo of the LLM you would like to use. The model configuration in the given repository must support text generation.
* `TEXT_GENERATION_MAX_SEQUENCE_LENGTH` (optional, default: 2048) - Maximum total number of tokens for a given conversation.
* `TEXT_GENERATION_MAX_NEW_TOKENS` (optional, default: 400) - Maximum new tokens to generate on each conversation turn.

#### OpenAI Configuration

* `OPENAI_API_KEY` (required) - Your OpenAI API key.
* `TEXT_GENERATION_MODEL` (required) - The OpenAI model to use.
* `TEXT_GENERATION_MAX_NEW_TOKENS` (optional, default: 400) - Maximum new tokens to generate on each conversation turn.

#### Generic Configuration

* `TEXT_GENERATION_API_URL` (required) - The OpenAI-compatible chat completions endpoint to use.
* `TEXT_GENERATION_MODEL` (required) - The generic model to use.
* `TEXT_GENERATION_API_KEY` (optional) - API key, if necessary, for the OpenAI-compatible endpoint.
* `TEXT_GENERATION_MAX_NEW_TOKENS` (optional, default: 400) - Maximum new tokens to generate on each conversation turn.

### Speech-to-Text Configuration

Currently, the only supported speech-to-text provider is Bumblebee. You can customize the speech-to-text model with:

* `SPEECH_TO_TEXT_MODEL` (required) - The HuggingFace model repo of the STT model you would like to use. `distil-whisper/distil-medium.en` is a good default for most configurations.

### Text-to-Speech Configuration

Currently, the only supported text-to-speech provider is ElevenLabs. There are a number of configuration options to customize the experience with ElevenLabs.

#### ElevenLabs Configuration

* `ELEVEN_LABS_API_KEY` (required) - Your ElevenLabs API key.
* `ELEVEN_LABS_MODEL_ID` (optional, default: "eleven_turbo_v2") - The ElevenLabs model ID to use. In most cases you should just leave the default.
* `ELEVEN_LABS_OPTIMIZE_STREAMING_LATENCY` (optional, default: 2) - The ElevenLabs optimization setting. Higher numbers result in better latency but will struggle with some pronounciations.
* `ELEVEN_LABS_OUTPUT_FORMAT` (optional, default: mp3_22050_32) - The ElevenLabs audio output format. Adjusting this can impact latency due to decoding requirements.

## Examples

* [Phoenix LiveView Example](https://github.com/seanmor5/echo_example)

## Acknowledgements

Thank you to [Andres Alejos](https://twitter.com/ac_alejos) for help setting up the VAD model and [Paulo Valente](https://twitter.com/polvalente) for some teachings on audio processing.