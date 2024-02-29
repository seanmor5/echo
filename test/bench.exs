Mix.install([
  {:benchee, "~> 1.0"},
  {:msgpax, "~> 2.0"},
  {:websockex, "~> 0.4.3"}
])

defmodule Wave do
  @moduledoc """
  This module contains the Wave struct, which defines fields for the WAVE file
  audio format.

  Similar to hound's WavSpec, which defines:
  * channels
  * sample_ate
  * bits_per_sample
  * sample_format
  """

  alias __MODULE__

  @enforce_keys [:audio_data, :format, :sample_rate, :channels]

  @type t :: %__MODULE__{
          audio_data: binary(),
          byte_rate: integer()
        }

  defstruct chunk_id: nil,
            chunk_size: nil,
            # FIXME
            format: "WAVE",
            subchunk1_id: nil,
            subchunk1_size: nil,
            audio_format: nil,
            channels: 1,
            sample_rate: nil,
            byte_rate: nil,
            block_align: nil,
            bits_per_sample: nil,
            subchunk2_id: nil,
            subchunk2_size: nil,
            audio_data: nil

  def new(audio_data, format, sample_rate, channels) do
    %Wave{
      chunk_id: nil,
      chunk_size: nil,
      format: nil,
      subchunk1_id: nil,
      subchunk1_size: nil,
      audio_format: format,
      channels: channels,
      sample_rate: sample_rate,
      byte_rate: nil,
      block_align: nil,
      bits_per_sample: nil,
      subchunk2_id: nil,
      subchunk2_size: nil,
      audio_data: audio_data
    }
  end

  @doc """
  Reads a WAVE file and returns binary data with {:ok, data}, or {:error, reason}
  `data` contains a struct with parsed informiation.
  """
  @spec read(String.t()) :: {:ok, Wave.t()} | {:error, String.t()}
  def read(path) do
    with true <- String.ends_with?(path, ".wav"),
         {:ok, data} <- File.read(path) do
      {:ok, data}
    else
      false -> {:error, "This library only accepts WAV files"}
      {:error, :enoent} -> {:error, "#{path} does not exist"}
      error -> error
    end
  end

  @spec parse([char]) :: map
  @doc """
  `parse` returns a map of headers and data for bitstring file data
  """
  def parse(file_data) when is_bitstring(file_data) do
    # TODO: Need to specify the type of the binary data, e.g., big-integer-size(32)?
    # TODO: Handle RIFX (big-endian encoded) files. Not default, not sure how common this is...

    ### RIFF (Resource Interchange File Format) chunk descriptor ###
    # Should contain the letters "RIFF" in ASCII form (0x52494646)
    # 4 bytes - (0-3) - big endian
    <<
      chunk_id::32-big,
      # 4 + (8 + subchunk1_size) + (8 + subchunk2_size) == 36 + subchunk2_size
      # The size of the rest of the chunk following this number. The size of the
      # whole file in bytes, minus 8 bytes for the two fields not included in the
      # count: chunk_id and chunk_size
      # 4 bytes - (4-7) - little endian
      chunk_size::32-little,
      # 4 bytes - (8-11) - big endian
      # WAVE format contains two sub-chunks: "fmt" and "data"
      # contains the letters "WAVE" (0x57415645 in big-endian)
      format::32-big,
      ### "fmt" subchunk  describing the format of the sound info in the data sub-chunk ###
      # contains the letters "fmt" - (0x666d7420 big-endian form)
      # 4 bytes (12-15) - big endian
      subchunk1_id::32-big,
      # 16 for PCM. The size of the rest of the subchunk that follows this number
      # 4 bytes (16-19) - little endian
      subchunk1_size::32-big,
      # PCM = 1 (Linear quantization); values other than 1 indicate some form
      # of compression
      # 2 bytes (20-22) - little endian
      audio_format::16-little,
      # Mono = 1, Stereo = 2, etc.
      # 2 bytes (22-23) - little endian
      channels::16-little,
      # E.g., 8000, 44_100, etc.
      # 4 bytes (24-27) - little endian
      sample_rate::32-little,
      # equal to sample_rate * channels * bits_per_sample / 8
      # 4 bytes - (28-31) - little endian
      byte_rate::32-little,
      # The number of bytes for one sample, including all channels.
      # equal to channels * bits_per_sample / 8
      # 2 bytes - (32-33) - little endian
      block_align::16-little,
      # 8 bits = 8, 16 bits = 16, etc.
      # 2 bytes - (34-35) - little endian
      bits_per_sample::16-little,
      # TODO: Handle this possibility
      # extra_param_size field - if PCM, this doesn't exist, otherwise 2 bytes
      # extra_params - space for extra parameters
      #
      ### "data" subchunk - size of the sound info and contains raw sound data ###
      #
      # Contains the letters "data" (0x64617461 big endian form)
      # 4 bytes - (36-39) - big endian
      subchunk2_id::32-big,
      # The number of bytes in the data. Can think of as the size of the read
      # of the subchunk following this number
      # equal to the num_samples * channels * bits_per_sample / 8
      # 4 bytes (40-43) - little endian
      subchunk2_size::32-little,
      # Actual sound data - little endian
      audio_data::little-binary
    >> = file_data

    %Wave{
      chunk_id: chunk_id,
      chunk_size: chunk_size,
      format: format,
      subchunk1_id: subchunk1_id,
      subchunk1_size: subchunk1_size,
      audio_format: audio_format,
      channels: channels,
      sample_rate: sample_rate,
      byte_rate: byte_rate,
      block_align: block_align,
      bits_per_sample: bits_per_sample,
      subchunk2_id: subchunk2_id,
      subchunk2_size: subchunk2_size,
      audio_data: audio_data
    }
  end
end

defmodule BenchClient do
  use WebSockex

  def open_stream(pid) do
    msg =
      Msgpax.pack!(%{type: "open", prompt: "Send me responses as fast as possible!"})
      |> IO.iodata_to_binary()

    WebSockex.send_frame(pid, {:text, msg})
    pid
  end

  def close_stream(pid) do
    msg = Msgpax.pack!(%{type: "close"}) |> IO.iodata_to_binary()
    WebSockex.send_frame(pid, {:text, msg})
  end

  def send_audio(pid, chunk) do
    msg = Msgpax.pack!(%{type: "audio", audio: Msgpax.Bin.new(chunk)})
    WebSockex.send_frame(pid, {:text, msg})
  end

  def handle_frame({:text, msg}, state) do
    unpacked = %{type: type} = Msgpax.unpack!(msg)

    received =
      case type do
        "audio" ->
          %{audio: audio} = unpacked
          <<token::8, audio::binary>> = audio
          :audio

        "token" ->
          :token

        "interrupt" ->
          :interrupt
      end

    {:ok, state}
  end
end

audio_clips = Path.join(File.cwd!(), "test/audio/") |> File.ls!() |> Enum.map(&Path.expand/1)

{:ok, pid} =
  WebSockex.start_link("ws://localhost:4001/conversation/websocket/", BenchClient, %{},
    debug: [:trace]
  )

Benchee.run(%{
  "open_close" => fn ->
    pid = BenchClient.open_stream(pid)
    BenchClient.close_stream(pid)
  end,
  "send_one_audio" => fn ->
    pid = BenchClient.open_stream(pid)
    {:ok, data} = Wave.read(audio_clips |> hd)

    Wave.parse(data).audio_data
    |> :binary.bin_to_list()
    |> Stream.chunk_every(1000)
    |> Stream.each(fn chunk ->
      IO.puts("Sending chunks!")
      BenchClient.send_audio(pid, chunk)
    end)
    |> Stream.run()

    BenchClient.close_stream(pid)
  end
})
