"""Tests for files/orca/orca-klipper-profile.py."""
import importlib.util
import json
import pathlib
import re

import pytest

SRC = pathlib.Path(__file__).resolve().parents[1] / "files/orca/orca-klipper-profile.py"
spec = importlib.util.spec_from_file_location("orca", SRC)
orca = importlib.util.module_from_spec(spec)
spec.loader.exec_module(orca)

MARLIN = {
    "name": "Ender-3 V2 CR Touch",
    "printer_settings_id": "Ender-3 V2 CR Touch",
    "inherits": "Creality Ender-3 V2 0.4 nozzle",
    "from": "User",
    "gcode_flavor": "marlin2",
    "machine_start_gcode": "G28\nG29 L0\n",
    "retraction_length": ["2.5"],
}


def test_klipper_profile_fields():
    p = orca.build(MARLIN, "klipper.local")
    assert p["name"] == p["printer_settings_id"] == "Ender-3 V2 Klipper CR Touch"
    assert p["inherits"] == "Creality Ender-3 V2 0.4 nozzle"
    assert p["gcode_flavor"] == "klipper"
    assert p["host_type"] == "octoprint"
    assert p["print_host"] == "klipper.local"
    assert p["machine_start_gcode"] == (
        "PRINT_START BED=[bed_temperature_initial_layer_single] "
        "EXTRUDER=[nozzle_temperature_initial_layer]")
    assert p["machine_end_gcode"] == "PRINT_END"
    assert p["layer_change_gcode"] == "PLR_SAVE LAYER=[layer_num] Z=[layer_z]"
    assert p["use_firmware_retraction"] == "1"
    assert p["use_relative_e_distances"] == "1"


def test_custom_name():
    p = orca.build(MARLIN, "h", name="My Klipper V2")
    assert p["name"] == p["printer_settings_id"] == "My Klipper V2"


def test_heating_left_to_print_start():
    # Orca writes M190/M104 before the start G-code for every flavor except
    # klipper, and a temperature M-code in the start G-code would heat before
    # PRINT_START homes and probes.
    p = orca.build(MARLIN, "h")
    assert p["gcode_flavor"] == "klipper"
    assert not re.search(r"\bM(104|109|140|190)\b", p["machine_start_gcode"])


def test_source_profile_untouched():
    before = dict(MARLIN)
    orca.build(MARLIN, "h")
    assert MARLIN == before


def test_machine_limits_allow_tuned_accel():
    p = orca.build(MARLIN, "h")
    for axis in ("x", "y", "extruding", "travel"):
        assert p[f"machine_max_acceleration_{axis}"] == ["3000", "3000"]


def test_fast_process_within_limits():
    p = orca.build_process("0.20mm Klipper fast")
    assert p["name"] == p["print_settings_id"] == "0.20mm Klipper fast"
    assert p["inherits"] == "0.20mm Standard @Creality Ender3V2"
    assert p["reduce_crossing_wall"] == "1"
    assert "wipe" not in p
    # must match the stock Creality Ender-3 V2 system profiles (generic key)
    assert p["print_extruder_variant"] == ["Direct Drive Standard"]
    accels = [int(v) for k, v in p.items() if k.endswith("_acceleration")]
    assert max(accels) <= 3000
    # flow at 0.45 mm line x 0.2 mm layer stays under a stock hotend's ~12 mm3/s
    assert 0.45 * 0.2 * int(p["sparse_infill_speed"]) < 12


def _orca_tree(tmp_path):
    mdir = tmp_path / "user" / "12345" / "machine"
    mdir.mkdir(parents=True)
    (mdir / "Ender-3 V2 CR Touch.json").write_text(json.dumps(MARLIN))
    (mdir / "Ender-3 V2 CR Touch.info").write_text("sync_info = update\nuser_id = 1\nsetting_id = x\nupdated_time = 5\n")
    return mdir


def test_main_writes_printer_only_without_process(tmp_path):
    mdir = _orca_tree(tmp_path)
    orca.main(["10.0.0.5", "--source", "Ender-3 V2 CR Touch", "--orca-user", str(tmp_path / "user")])
    out = json.loads((mdir / "Ender-3 V2 Klipper CR Touch.json").read_text())
    assert out["print_host"] == "10.0.0.5"
    info = (mdir / "Ender-3 V2 Klipper CR Touch.info").read_text()
    assert "user_id = 1" in info and "setting_id = x" not in info
    assert not (mdir.parent / "process").exists()
    # the source profile is left as it was
    assert json.loads((mdir / "Ender-3 V2 CR Touch.json").read_text()) == MARLIN


def test_main_writes_process_when_named(tmp_path):
    mdir = _orca_tree(tmp_path)
    orca.main(["h", "--source", "Ender-3 V2 CR Touch", "--process", "Fast",
               "--orca-user", str(tmp_path / "user")])
    proc = json.loads((mdir.parent / "process" / "Fast.json").read_text())
    assert proc["name"] == "Fast"
    assert "base_id = " in (mdir.parent / "process" / "Fast.info").read_text()


def test_main_missing_source_exits(tmp_path):
    _orca_tree(tmp_path)
    with pytest.raises(SystemExit):
        orca.main(["h", "--source", "Nope", "--orca-user", str(tmp_path / "user")])
