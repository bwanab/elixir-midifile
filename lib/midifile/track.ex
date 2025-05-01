defmodule Midifile.Track do
  @type t() :: %__MODULE__{
    name: String.t(),
    events: list()
  }

  alias Midifile.Event

  defstruct name: "Unnamed",
    events: []

  @spec new(String.t(), MusicPrims.note_sequence(), integer()) :: t()
  def new(name, notes, tpqn \\ 960) do
    e1 = [%Midifile.Event{symbol: :seq_name, delta_time: 0, bytes: name}]
    events = Enum.map(notes, &(Midifile.Event.new(:note, &1, tpqn)))
    e_last = [%Midifile.Event{symbol: :track_end, delta_time: 0, bytes: []}]

    %Midifile.Track{
      name: name,
      events: List.flatten(e1 ++ events ++ e_last)
    }
  end

  def instrument(%Midifile.Track{events: nil}), do: ""
  def instrument(%Midifile.Track{events: []}),  do: ""
  def instrument(%Midifile.Track{events: list})  do
    case Enum.find(list, &(&1.symbol == :instrument)) do
      %Event{bytes: bytes} -> bytes
      nil -> ""
    end
  end

  def quantize(track, n) do
    %{track | events: Event.quantize(track.events, n)}
  end
end
