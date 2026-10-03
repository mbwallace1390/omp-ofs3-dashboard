"""Desktop checks of the real OFS3 sensor resolver; no radio is emulated."""
from pathlib import Path
import unittest

from lupa.lua53 import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]


class TelemetryTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            sourceReads = 0
            selectedSource = nil
            ofs3 = {
                session = {}, preferences = {localizations = {}},
                utils = {log = function() end, simSensors = function() return 0 end}
            }
            package.loaded.ofs3 = ofs3
            system = {
                getVersion = function() return {simulation = false} end,
                getSource = function(probe)
                    sourceReads = sourceReads + 1
                    lastProbe = probe
                    return selectedSource
                end
            }
        ''')
        source = (ROOT / "src/ofs3/lib/telemetry.lua").read_text(encoding="utf-8")
        self.lua.globals().telemetry = self.lua.execute(source)

    def test_missing_source_and_unknown_sensor_return_nil(self):
        self.lua.execute('''
            telemetry.setProtocol("crsf")
            assert(telemetry.getSensor("voltage") == nil)
            assert(telemetry.getSensor("not-a-sensor") == nil)
        ''')

    def test_zero_is_preserved_and_source_is_cached(self):
        self.lua.execute('''
            selectedSource = {value = function() return 0 end}
            telemetry.setProtocol("crsf")
            local value, _, unit = telemetry.getSensor("voltage")
            assert(value == 0 and unit == "V")
            assert(lastProbe.crsfId == 0x08)
            local reads = sourceReads
            assert(telemetry.getSensor("voltage") == 0)
            assert(sourceReads == reads)
        ''')

    def test_protocol_change_discards_previous_source(self):
        self.lua.execute('''
            selectedSource = {value = function() return 24 end}
            telemetry.setProtocol("crsf")
            assert(telemetry.getSensor("voltage") == 24)
            selectedSource = {value = function() return 25 end}
            telemetry.setProtocol("sport")
            assert(telemetry.getSensor("voltage") == 25)
            assert(lastProbe.appId == 0x0B50)
        ''')

    def test_reset_clears_protocol_cache_and_stats(self):
        self.lua.execute('''
            selectedSource = {value = function() return 24 end}
            telemetry.setProtocol("sport")
            assert(telemetry.getSensor("voltage") == 24)
            telemetry.sensorStats.voltage = {min = 23, max = 25}
            telemetry.reset()
            assert(telemetry.getSensorProtocol() == "unknown")
            assert(telemetry.getSensorStats("voltage").min == nil)
            assert(telemetry.getSensor("voltage") == nil)
            assert(not telemetry.active())
            ofs3.session.telemetryState = true
            assert(telemetry.active())
        ''')

    def test_source_lua_parses(self):
        compile_lua = self.lua.eval('function(s, name) local fn, err = load(s, name); return fn ~= nil, err end')
        files = sorted((ROOT / "src/ofs3").rglob("*.lua"))
        self.assertTrue(files, "No source Lua files found")
        for path in files:
            with self.subTest(path=path.relative_to(ROOT)):
                ok, error = compile_lua(path.read_text(encoding="utf-8"), "@" + path.as_posix())
                self.assertTrue(ok, error)


if __name__ == "__main__":
    unittest.main()
