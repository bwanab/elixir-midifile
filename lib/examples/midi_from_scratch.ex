defmodule Examples.MidiFromScratch do
  alias Midifile.Event
  alias Midifile.Track
  alias Midifile.Sequence

  def from_scratch() do
    e = %Event{symbol: :on, delta_time: 100, bytes: [0x92, 64, 127]}
     t = %Track{events: [e, e, e]}

     ct = %Track{
       events: [
         %Event{symbol: :seq_name, bytes: "Unnamed"},
         %Event{symbol: :tempo, bytes: [trunc(60_000_000 / 82)]}
       ]
     }

     # Create a sequence with the new time_basis structure using metrical time
     metrical_seq = %Sequence{
       time_basis: :metrical_time,
       ticks_per_quarter_note: 480,
       smpte_format: nil,
       ticks_per_frame: nil,
       conductor_track: ct,
       tracks: [t, t, t]
      }

     {:ok, %{seq: metrical_seq, track: t}}
   end


end
