from app.services.timetable_ocr import RawBlock, RawTimetable, normalize


def b(name, weekday, start, end):
    return RawBlock(name=name, weekday=weekday, start=start, end=end)


def run(blocks, untimed=()):
    return normalize(RawTimetable(blocks=list(blocks), untimed=list(untimed)))


def slots(subject):
    return [(s.weekday, s.start, s.end) for s in subject.slots]


def test_groups_same_subject_across_days():
    result = run(
        [b("데이터과학기초", 1, "10:30", "12:00"), b("데이터과학기초", 3, "10:30", "12:00")]
    )
    assert len(result) == 1
    assert slots(result[0]) == [(1, "10:30", "12:00"), (3, "10:30", "12:00")]


def test_merges_touching_blocks_same_day():
    result = run([b("자료구조", 0, "09:00", "10:00"), b("자료구조", 0, "10:00", "11:00")])
    assert slots(result[0]) == [(0, "09:00", "11:00")]


def test_drops_duplicate_block():
    result = run([b("자료구조", 0, "09:00", "10:00"), b("자료구조", 0, "09:00", "10:00")])
    assert len(result[0].slots) == 1


def test_pads_and_snaps_times():
    result = run([b("운영체제", 4, "9:00", "10:28")])
    assert slots(result[0]) == [(4, "09:00", "10:30")]


def test_snaps_to_half_hour_boundaries():
    result = run([b("A", 0, "10:14", "10:45"), b("B", 1, "10:15", "11:44")])
    by_name = {s.name: slots(s) for s in result}
    assert by_name["A"] == [(0, "10:00", "11:00")]
    assert by_name["B"] == [(1, "10:30", "11:30")]


def test_drops_slot_collapsed_by_snapping():
    result = run([b("C", 2, "10:05", "10:10")])
    assert [s.name for s in result] == ["C"]
    assert result[0].slots == []


def test_invalid_slot_keeps_subject():
    result = run(
        [
            b("이산수학", 7, "15:00", "16:30"),
            b("확률과 통계", 2, "12:00", "11:00"),
            b("컴퓨터구조", 1, "오후 1시", "14:30"),
        ]
    )
    assert {s.name for s in result} == {"이산수학", "확률과 통계", "컴퓨터구조"}
    assert all(s.slots == [] for s in result)


def test_untimed_subjects_added_last():
    result = run([b("자료구조", 0, "10:30", "12:00")], untimed=["사이버강의 예시", "자료구조"])
    assert [s.name for s in result] == ["자료구조", "사이버강의 예시"]
    assert result[1].slots == []
    assert slots(result[0]) == [(0, "10:30", "12:00")]


def test_orders_subjects_by_first_slot():
    result = run(
        [
            b("금요일과목", 4, "09:00", "10:00"),
            b("월요일과목", 0, "13:00", "14:00"),
            b("월오전", 0, "09:00", "10:00"),
        ]
    )
    assert [s.name for s in result] == ["월오전", "월요일과목", "금요일과목"]


def test_cleans_names():
    result = run([b("  자료  구조 ", 0, "09:00", "10:00"), b("", 1, "09:00", "10:00")])
    assert [s.name for s in result] == ["자료 구조"]


def test_saturday_kept():
    result = run([b("토요일수업", 5, "09:00", "12:00")])
    assert result[0].slots[0].weekday == 5
