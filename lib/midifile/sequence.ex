defmodule Midifile.Sequence do
  @type time_basis_type :: :metrical_time | :smpte
  @type track_list :: list(Midifile.Track.t())

  @type t() :: %__MODULE__{
    time_basis: time_basis_type(),
    ticks_per_quarter_note: integer() | nil,
    smpte_format: integer() | nil,
    ticks_per_frame: integer() | nil,     # Used when time_basis is :smpte
    # Track structure
    conductor_track: Midifile.Track.t() | nil,
    tracks: track_list()

  }
  alias Midifile.Event
  alias Midifile.Track
  alias Midifile.Sequence

  @default_bpm 120
  @default_ppqn 960


  defstruct format: 1,
            # Explicit time basis structure
            time_basis: :metrical_time,  # :metrical_time or :smpte
            ticks_per_quarter_note: @default_ppqn, # Used when time_basis is :metrical_time
            smpte_format: nil,           # 24, 25, 29, or 30 - used when time_basis is :smpte
            ticks_per_frame: nil,        # Used when time_basis is :smpte
            # Track structure
            conductor_track: nil,
            tracks: []

  # NOTE: very limited: assumes 4/4 time, no overlapping events on any track.
  @spec new(String.t(), integer(), track_list(), integer() ):: t()
  def new(name, bpm, tracks, tpqn) do

    ct = %Track{
      events: [
        %Event{symbol: :seq_name, delta_time: 0, bytes: name},
        %Midifile.Event{
         symbol: :time_signature,
         delta_time: 0,
         bytes: [<<4, 2, 24, 8>>]    # 4/4 time
       },
        %Event{symbol: :tempo, bytes: [trunc(60_000_000 / bpm)]},
        %Midifile.Event{symbol: :track_end, delta_time: 0, bytes: []}
      ]
    }

    # Create a sequence with the new time_basis structure using metrical time
    metrical_seq = %Sequence{
     format: 1,
     time_basis: :metrical_time,
     ticks_per_quarter_note: tpqn,
     smpte_format: nil,
     ticks_per_frame: nil,
     conductor_track: ct,
     tracks: tracks
   }

    metrical_seq
  end

  def name(%Midifile.Sequence{conductor_track: nil}), do: ""
  def name(%Midifile.Sequence{conductor_track: %Midifile.Track{events: []}}), do: ""

  def name(%Midifile.Sequence{conductor_track: %Midifile.Track{events: list}}) do
    case Enum.find(list, &(&1.symbol == :seq_name)) do
      %Midifile.Event{bytes: bytes} -> bytes
      nil -> ""
    end
  end

  def bpm(%Midifile.Sequence{conductor_track: nil}), do: @default_bpm
  def bpm(%Midifile.Sequence{conductor_track: %Midifile.Track{events: []}}), do: @default_bpm

  def bpm(%Midifile.Sequence{conductor_track: %Midifile.Track{events: list}}) do
    case Enum.find(list, &(&1.symbol == :tempo)) do
      %Midifile.Event{bytes: [microsecs_per_beat | _]} ->
        trunc(60_000_000 / microsecs_per_beat)

      nil ->
        @default_bpm
    end
  end

  def set_bpm(%Midifile.Sequence{conductor_track: nil} = seq, _bpm_value) do
    IO.warn("Cannot set BPM: Sequence has no conductor track")
    seq
  end

  def set_bpm(%Midifile.Sequence{conductor_track: %Midifile.Track{events: []}} = seq, _bpm_value) do
    IO.warn("Cannot set BPM: Conductor track has no events")
    seq
  end

  def set_bpm(%Midifile.Sequence{conductor_track: %Midifile.Track{events: list}} = seq, bpm_value)
      when is_integer(bpm_value) do
    microsecs_per_beat = trunc(60_000_000 / bpm_value)

    updated_events =
      Enum.map(list, fn event ->
        case event.symbol do
          :tempo -> %{event | bytes: [microsecs_per_beat | tl(event.bytes)]}
          _ -> event
        end
      end)

    updated_conductor = %{seq.conductor_track | events: updated_events}
    %{seq | conductor_track: updated_conductor}
  end

  @doc """
  Returns true if the sequence uses a metrical time division (ticks per quarter note).
  """
  def metrical_time?(%Midifile.Sequence{time_basis: :metrical_time}), do: true
  def metrical_time?(_), do: false

  @doc """
  Returns true if the sequence uses SMPTE time division format.
  """
  def smpte_format?(%Midifile.Sequence{time_basis: :smpte}), do: true
  def smpte_format?(_), do: false

  @doc """
  Returns the pulses per quarter note (PPQN) value.
  This is only valid if the sequence uses metrical time.
  If the sequence uses SMPTE format, returns nil.
  """
  def ppqn(%Midifile.Sequence{time_basis: :metrical_time, ticks_per_quarter_note: tpqn}), do: tpqn
  def ppqn(_), do: nil

  @doc """
  Returns the SMPTE frames per second value, if the sequence uses SMPTE format.
  According to the MIDI spec, this will be one of: 24, 25, 29 (for 29.97, 30 drop frame),
  or 30 frames per second.
  Returns nil if the sequence uses metrical time format.
  """
  def smpte_frames_per_second(%Midifile.Sequence{time_basis: :smpte, smpte_format: format}), do: format
  def smpte_frames_per_second(_), do: nil

  @doc """
  Returns the SMPTE ticks per frame value, if the sequence uses SMPTE format.
  This is the resolution within each frame, typically: 4 (MIDI Time Code), 8, 10,
  80 (bit resolution), or 100.
  Returns nil if the sequence uses metrical time format.
  """
  def smpte_ticks_per_frame(%Midifile.Sequence{time_basis: :smpte, ticks_per_frame: ticks}), do: ticks
  def smpte_ticks_per_frame(_), do: nil

  @doc """
  Creates a new sequence with metrical time basis (ticks per quarter note).
  """
  def with_metrical_time(sequence, ticks_per_quarter_note) when is_integer(ticks_per_quarter_note) and ticks_per_quarter_note in 1..32767 do
    %Midifile.Sequence{
      sequence |
      time_basis: :metrical_time,
      ticks_per_quarter_note: ticks_per_quarter_note,
      smpte_format: nil,
      ticks_per_frame: nil
    }
  end

  @doc """
  Creates a new sequence with SMPTE time basis.

  Valid frames_per_second values are: 24, 25, 29 (for 29.97 drop frame), and 30.
  """
  def with_smpte_time(sequence, frames_per_second, ticks_per_frame)
      when frames_per_second in [24, 25, 29, 30] and
           is_integer(ticks_per_frame) and
           ticks_per_frame in 1..255 do

    %Midifile.Sequence{
      sequence |
      time_basis: :smpte,
      ticks_per_quarter_note: nil,
      smpte_format: frames_per_second,
      ticks_per_frame: ticks_per_frame
    }
  end

  # Legacy support functions that work with raw division values

  @doc """
  Creates a standard metrical time division value from a pulses per quarter note (PPQN) value.
  This sets bit 15 to 0 and uses the lower 15 bits for the PPQN.

  This is a low-level function for compatibility. Prefer using with_metrical_time/2 instead.
  """
  def create_metrical_division(ppqn) when is_integer(ppqn) and ppqn in 1..32767 do
    <<0::size(1), ppqn::size(15)>>
  end

  @doc """
  Creates an SMPTE format division value from frames per second and ticks per frame values.
  This sets bit 15 to 1, uses bits 8-14 for the negative of frames per second (in two's complement),
  and the lower 8 bits for ticks per frame.

  Valid frames_per_second values are: 24, 25, 29 (for 29.97 drop frame), and 30.

  This is a low-level function for compatibility. Prefer using with_smpte_time/3 instead.
  """
  def create_smpte_division(frames_per_second, ticks_per_frame)
      when frames_per_second in [24, 25, 29, 30] and
           is_integer(ticks_per_frame) and
           ticks_per_frame in 1..255 do

    # Convert to negative two's complement 7-bit value
    frames_bits = case frames_per_second do
      24 -> 0b1101000  # -24 in 7-bit two's complement (0x68)
      25 -> 0b1100111  # -25 in 7-bit two's complement (0x67)
      29 -> 0b1100011  # -29 in 7-bit two's complement (0x63, for 30 drop frame)
      30 -> 0b1100010  # -30 in 7-bit two's complement (0x62)
    end

    <<1::size(1), frames_bits::size(7), ticks_per_frame::size(8)>>
  end

  @doc """
  Calculate the division value from a sequence's time basis fields.

  This replaces the old division field with a calculated property based on
  the explicit time basis settings. This ensures there's only one source of
  truth for time basis information.

  ## Returns
    * For metrical time: the ticks_per_quarter_note value
    * For SMPTE time: the encoded SMPTE division value
    * Default of 480 if the time_basis is invalid or fields are missing
  """
  def division(%__MODULE__{time_basis: :metrical_time, ticks_per_quarter_note: tpqn})
      when not is_nil(tpqn) do
    tpqn
  end

  def division(%__MODULE__{time_basis: :smpte, smpte_format: format, ticks_per_frame: tpf})
      when not is_nil(format) and not is_nil(tpf) do
    # Calculate division value from SMPTE format
    division_binary = create_smpte_division(format, tpf)
    :binary.decode_unsigned(division_binary)
  end

  def division(_), do: @default_ppqn  # Default if missing or invalid time_basis

  @doc """
  Parse a division value from a MIDI file and return appropriate time basis values.

  This function is meant to be used by the Reader module to initialize a new Sequence
  with the correct time basis values based on the division value from a MIDI file.

  Returns a map with :time_basis, :ticks_per_quarter_note, :smpte_format, :ticks_per_frame.
  """
  def parse_division(division) when is_integer(division) do
    <<format_bit::size(1), rest::size(15)>> = <<division::size(16)>>

    if format_bit == 0 do
      # Metrical time
      %{
        time_basis: :metrical_time,
        ticks_per_quarter_note: rest,
        smpte_format: nil,
        ticks_per_frame: nil
      }
    else
      # SMPTE time
      <<frames_bits::size(7), ticks::size(8)>> = <<rest::size(15)>>

      # Convert from two's complement negative value
      frames_per_second = case frames_bits do
        0b1101000 -> 24  # -24 in 7-bit two's complement
        0b1100111 -> 25  # -25 in 7-bit two's complement
        0b1100011 -> 29  # -29 in 7-bit two's complement (for 30 drop frame)
        0b1100010 -> 30  # -30 in 7-bit two's complement
        _ -> nil         # Invalid value
      end

      %{
        time_basis: :smpte,
        ticks_per_quarter_note: nil,
        smpte_format: frames_per_second,
        ticks_per_frame: ticks
      }
    end
  end
end
