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

  test "name", context do
    assert Sequence.name(context[:seq]) == "Unnamed"
  end

  test "bpm", context do
    assert Sequence.bpm(context[:seq]) == 82
  end

  test "ppqn with metrical format", context do
    assert Sequence.ppqn(context[:seq]) == 480
  end

  test "metrical_time? with metrical format", context do
    assert Sequence.metrical_time?(context[:seq]) == true
  end

  test "smpte_format? with metrical format", context do
    assert Sequence.smpte_format?(context[:seq]) == false
  end

  test "metrical_time? with SMPTE format" do
    # Create a sequence with SMPTE time basis (25 fps, 40 ticks per frame)
    seq = %Sequence{
      time_basis: :smpte,
      ticks_per_quarter_note: nil,
      smpte_format: 25,
      ticks_per_frame: 40
    }

    assert Sequence.metrical_time?(seq) == false
  end

  test "smpte_format? with SMPTE format" do
    # Create a sequence with SMPTE time basis (25 fps, 40 ticks per frame)
    seq = %Sequence{
      time_basis: :smpte,
      ticks_per_quarter_note: nil,
      smpte_format: 25,
      ticks_per_frame: 40
    }

    assert Sequence.smpte_format?(seq) == true
  end

  test "ppqn with SMPTE format" do
    # Create a sequence with SMPTE time basis (25 fps, 40 ticks per frame)
    seq = %Sequence{
      time_basis: :smpte,
      ticks_per_quarter_note: nil,
      smpte_format: 25,
      ticks_per_frame: 40
    }

    assert Sequence.ppqn(seq) == nil
  end

  test "smpte_frames_per_second" do
    # Test all valid SMPTE frames per second values
    # Use the new structure directly
    seq_24fps = %Sequence{time_basis: :smpte, smpte_format: 24, ticks_per_frame: 4}
    seq_25fps = %Sequence{time_basis: :smpte, smpte_format: 25, ticks_per_frame: 4}
    seq_29fps = %Sequence{time_basis: :smpte, smpte_format: 29, ticks_per_frame: 4}
    seq_30fps = %Sequence{time_basis: :smpte, smpte_format: 30, ticks_per_frame: 4}

    assert Sequence.smpte_frames_per_second(seq_24fps) == 24
    assert Sequence.smpte_frames_per_second(seq_25fps) == 25
    assert Sequence.smpte_frames_per_second(seq_29fps) == 29
    assert Sequence.smpte_frames_per_second(seq_30fps) == 30

    # Should return nil for metrical time format
    metrical_seq = %Sequence{time_basis: :metrical_time, ticks_per_quarter_note: 480}
    assert Sequence.smpte_frames_per_second(metrical_seq) == nil
  end

  test "smpte_ticks_per_frame" do
    # Test various ticks per frame values with the new structure
    seq_4tpf = %Sequence{time_basis: :smpte, smpte_format: 25, ticks_per_frame: 4}
    seq_8tpf = %Sequence{time_basis: :smpte, smpte_format: 25, ticks_per_frame: 8}
    seq_10tpf = %Sequence{time_basis: :smpte, smpte_format: 25, ticks_per_frame: 10}
    seq_80tpf = %Sequence{time_basis: :smpte, smpte_format: 25, ticks_per_frame: 80}
    seq_100tpf = %Sequence{time_basis: :smpte, smpte_format: 25, ticks_per_frame: 100}

    assert Sequence.smpte_ticks_per_frame(seq_4tpf) == 4
    assert Sequence.smpte_ticks_per_frame(seq_8tpf) == 8
    assert Sequence.smpte_ticks_per_frame(seq_10tpf) == 10
    assert Sequence.smpte_ticks_per_frame(seq_80tpf) == 80
    assert Sequence.smpte_ticks_per_frame(seq_100tpf) == 100

    # Should return nil for metrical time format
    metrical_seq = %Sequence{time_basis: :metrical_time, ticks_per_quarter_note: 480}
    assert Sequence.smpte_ticks_per_frame(metrical_seq) == nil
  end

  test "create_metrical_division" do
    # Test creating metrical division values
    assert Sequence.create_metrical_division(480) == <<0::size(1), 480::size(15)>>

    # Verify value through binary parsing
    ppqn_96 = Sequence.create_metrical_division(96)
    <<format_bit::size(1), ppqn::size(15)>> = ppqn_96
    assert format_bit == 0
    assert ppqn == 96
  end

  test "create_smpte_division" do
    # Test creating SMPTE division values for all valid frame rates
    smpte_24_4 = Sequence.create_smpte_division(24, 4)
    smpte_25_40 = Sequence.create_smpte_division(25, 40)
    smpte_29_80 = Sequence.create_smpte_division(29, 80)
    smpte_30_100 = Sequence.create_smpte_division(30, 100)

    # Verify values through binary parsing
    <<format_bit_24::size(1), frames_bits_24::size(7), ticks_24::size(8)>> = smpte_24_4
    <<format_bit_25::size(1), frames_bits_25::size(7), ticks_25::size(8)>> = smpte_25_40
    <<format_bit_29::size(1), frames_bits_29::size(7), ticks_29::size(8)>> = smpte_29_80
    <<format_bit_30::size(1), frames_bits_30::size(7), ticks_30::size(8)>> = smpte_30_100

    # Check format bit is 1 for all
    assert format_bit_24 == 1
    assert format_bit_25 == 1
    assert format_bit_29 == 1
    assert format_bit_30 == 1

    # Check frames bits (7 bits, 2's complement negative)
    assert frames_bits_24 == 0b1101000  # -24 in 7-bit two's complement (0x68)
    assert frames_bits_25 == 0b1100111  # -25 in 7-bit two's complement (0x67)
    assert frames_bits_29 == 0b1100011  # -29 in 7-bit two's complement (0x63)
    assert frames_bits_30 == 0b1100010  # -30 in 7-bit two's complement (0x62)

    # Check ticks per frame values
    assert ticks_24 == 4
    assert ticks_25 == 40
    assert ticks_29 == 80
    assert ticks_30 == 100
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

  test "set_bpm with nil conductor_track returns unchanged sequence" do
    seq = %Sequence{conductor_track: nil}
    # Should return the same sequence unchanged
    assert Sequence.set_bpm(seq, 120) == seq
  end

  test "set_bpm with empty events returns unchanged sequence" do
    seq = %Sequence{conductor_track: %Track{events: []}}
    # Should return the same sequence unchanged
    assert Sequence.set_bpm(seq, 120) == seq
  end

  test "with_metrical_time" do
    # Start with a sequence that has SMPTE time basis
    smpte_seq = %Sequence{
      time_basis: :smpte,
      ticks_per_quarter_note: nil,
      smpte_format: 25,
      ticks_per_frame: 40
    }

    # Convert to metrical time
    metrical_seq = Sequence.with_metrical_time(smpte_seq, 480)

    # Verify all properties were updated correctly
    assert metrical_seq.time_basis == :metrical_time
    assert metrical_seq.ticks_per_quarter_note == 480
    assert metrical_seq.smpte_format == nil
    assert metrical_seq.ticks_per_frame == nil

    # Verify the division is calculated correctly
    assert Sequence.division(metrical_seq) == 480
  end

  test "with_smpte_time" do
    # Start with a sequence that has metrical time basis
    metrical_seq = %Sequence{
      time_basis: :metrical_time,
      ticks_per_quarter_note: 480,
      smpte_format: nil,
      ticks_per_frame: nil
    }

    # Convert to SMPTE time
    smpte_seq = Sequence.with_smpte_time(metrical_seq, 25, 40)

    # Verify all properties were updated correctly
    assert smpte_seq.time_basis == :smpte
    assert smpte_seq.ticks_per_quarter_note == nil
    assert smpte_seq.smpte_format == 25
    assert smpte_seq.ticks_per_frame == 40

    # Verify the division is calculated correctly
    smpte_division = :binary.decode_unsigned(Sequence.create_smpte_division(25, 40))
    assert Sequence.division(smpte_seq) == smpte_division
  end

  test "parse_division with metrical time" do
    # Test parsing a metrical time division value
    division = 480
    result = Sequence.parse_division(division)

    assert result.time_basis == :metrical_time
    assert result.ticks_per_quarter_note == 480
    assert result.smpte_format == nil
    assert result.ticks_per_frame == nil
  end

  test "parse_division with SMPTE time" do
    # Test parsing SMPTE division values for all valid frame rates
    # Create SMPTE divisions for each format
    div_24fps = :binary.decode_unsigned(Sequence.create_smpte_division(24, 4))
    div_25fps = :binary.decode_unsigned(Sequence.create_smpte_division(25, 40))
    div_29fps = :binary.decode_unsigned(Sequence.create_smpte_division(29, 80))
    div_30fps = :binary.decode_unsigned(Sequence.create_smpte_division(30, 100))

    # Parse each division
    result_24 = Sequence.parse_division(div_24fps)
    result_25 = Sequence.parse_division(div_25fps)
    result_29 = Sequence.parse_division(div_29fps)
    result_30 = Sequence.parse_division(div_30fps)

    # Verify 24 fps result
    assert result_24.time_basis == :smpte
    assert result_24.ticks_per_quarter_note == nil
    assert result_24.smpte_format == 24
    assert result_24.ticks_per_frame == 4

    # Verify 25 fps result
    assert result_25.time_basis == :smpte
    assert result_25.ticks_per_quarter_note == nil
    assert result_25.smpte_format == 25
    assert result_25.ticks_per_frame == 40

    # Verify 29.97 fps result
    assert result_29.time_basis == :smpte
    assert result_29.ticks_per_quarter_note == nil
    assert result_29.smpte_format == 29
    assert result_29.ticks_per_frame == 80

    # Verify 30 fps result
    assert result_30.time_basis == :smpte
    assert result_30.ticks_per_quarter_note == nil
    assert result_30.smpte_format == 30
    assert result_30.ticks_per_frame == 100
  end

  test "division function with metrical time" do
    # Test division calculation for metrical time
    seq = %Sequence{
      time_basis: :metrical_time,
      ticks_per_quarter_note: 480,
      smpte_format: nil,
      ticks_per_frame: nil
    }

    assert Sequence.division(seq) == 480
  end

  test "division function with SMPTE time" do
    # Test division calculation for SMPTE time
    seq = %Sequence{
      time_basis: :smpte,
      ticks_per_quarter_note: nil,
      smpte_format: 25,
      ticks_per_frame: 40
    }

    # Calculate expected division
    expected = :binary.decode_unsigned(Sequence.create_smpte_division(25, 40))

    assert Sequence.division(seq) == expected
  end
end
