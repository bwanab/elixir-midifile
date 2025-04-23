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

  def ppqn(seq) do
    <<0::size(1), ppqn::size(15)>> = <<seq.division::size(16)>>
    ppqn
  end

  # TODO: handle SMPTE (first bit 1, -frame/sec (7 bits), ticks/frame (8 bits))
end
