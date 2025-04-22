defmodule Midifile.Track do

  alias Midifile.Event

  defstruct name: "Unnamed",
    events: []

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
