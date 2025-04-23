defmodule SequenceTest do
  use ExUnit.Case
  alias Midifile.Sequence
  alias Midifile.Track
  alias Midifile.Event

  setup do
    e = %Event{symbol: :on, delta_time: 100, bytes: [0x92, 64, 127]}
    t = %Track{events: [e, e, e]}

    ct = %Track{
      events: [
        %Event{symbol: :seq_name, bytes: "Unnamed"},
        %Event{symbol: :tempo, bytes: [trunc(60_000_000 / 82)]}
      ]
    }

    {:ok, %{seq: %Sequence{division: 480, conductor_track: ct, tracks: [t, t, t]}, track: t}}
  end

  test "name", context do
    assert Sequence.name(context[:seq]) == "Unnamed"
  end

  test "bpm", context do
    assert Sequence.bpm(context[:seq]) == 82
  end

  test "ppqn", context do
    assert Sequence.ppqn(context[:seq]) == 480
  end

  test "set_bpm", context do
    original_bpm = Sequence.bpm(context[:seq])
    new_bpm = original_bpm + 10
    new_seq = Sequence.set_bpm(context[:seq], new_bpm)

    # Check that a new sequence is returned
    assert new_seq != context[:seq]

    # Check that the BPM was updated
    assert Sequence.bpm(new_seq) == new_bpm

    # Check that original sequence is unchanged
    assert Sequence.bpm(context[:seq]) == original_bpm
  end

  test "set_bpm with nil conductor_track" do
    seq = %Sequence{conductor_track: nil}
    # Should return the same sequence and print a warning
    assert Sequence.set_bpm(seq, 120) == seq
  end

  test "set_bpm with empty events" do
    seq = %Sequence{conductor_track: %Track{events: []}}
    # Should return the same sequence and print a warning
    assert Sequence.set_bpm(seq, 120) == seq
  end
end
