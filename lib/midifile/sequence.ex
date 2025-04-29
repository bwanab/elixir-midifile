defmodule Midifile.Sequence do
  @default_bpm 120

  defstruct format: 1, division: 480, conductor_track: nil, tracks: []

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
  In this case, bit 15 of the division word is 0.
  """
  def metrical_time?(seq) do
    <<format_bit::size(1), _::size(15)>> = <<seq.division::size(16)>>
    format_bit == 0
  end

  @doc """
  Returns true if the sequence uses SMPTE time division format.
  In this case, bit 15 of the division word is 1.
  """
  def smpte_format?(seq) do
    <<format_bit::size(1), _::size(15)>> = <<seq.division::size(16)>>
    format_bit == 1
  end

  @doc """
  Returns the pulses per quarter note (PPQN) value.
  This is only valid if the sequence uses metrical time (bit 15 of division is 0).
  If the sequence uses SMPTE format, returns nil.
  """
  def ppqn(seq) do
    if metrical_time?(seq) do
      <<0::size(1), ppqn::size(15)>> = <<seq.division::size(16)>>
      ppqn
    else
      nil
    end
  end

  @doc """
  Returns the SMPTE frames per second value, if the sequence uses SMPTE format.
  According to the MIDI spec, this will be one of: 24, 25, 29 (for 29.97, 30 drop frame),
  or 30 frames per second.
  Returns nil if the sequence uses metrical time format.
  """
  def smpte_frames_per_second(seq) do
    if smpte_format?(seq) do
      <<1::size(1), frames_bits::size(7), _::size(8)>> = <<seq.division::size(16)>>
      
      # Convert from two's complement negative value
      # The frames value is stored as a negative number in two's complement form
      case frames_bits do
        0b1101000 -> 24  # -24 in 7-bit two's complement (0x68)
        0b1100111 -> 25  # -25 in 7-bit two's complement (0x67)
        0b1100011 -> 29  # -29 in 7-bit two's complement (0x63)
        0b1100010 -> 30  # -30 in 7-bit two's complement (0x62)
        _ -> nil         # Invalid value
      end
    else
      nil
    end
  end

  @doc """
  Returns the SMPTE ticks per frame value, if the sequence uses SMPTE format.
  This is the resolution within each frame, typically: 4 (MIDI Time Code), 8, 10,
  80 (bit resolution), or 100.
  Returns nil if the sequence uses metrical time format.
  """
  def smpte_ticks_per_frame(seq) do
    if smpte_format?(seq) do
      <<_::size(8), ticks::size(8)>> = <<seq.division::size(16)>>
      ticks
    else
      nil
    end
  end

  @doc """
  Creates a standard metrical time division value from a pulses per quarter note (PPQN) value.
  This sets bit 15 to 0 and uses the lower 15 bits for the PPQN.
  """
  def create_metrical_division(ppqn) when is_integer(ppqn) and ppqn in 1..32767 do
    <<0::size(1), ppqn::size(15)>>
  end

  @doc """
  Creates an SMPTE format division value from frames per second and ticks per frame values.
  This sets bit 15 to 1, uses bits 8-14 for the negative of frames per second (in two's complement),
  and the lower 8 bits for ticks per frame.
  
  Valid frames_per_second values are: 24, 25, 29 (for 29.97 drop frame), and 30.
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
end
