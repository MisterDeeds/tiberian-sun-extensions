// Tiberian Sun Extensions - maps: theater tiles (TMP headers), map cells, overlay, and a small
// builder for missions (houses, structures, units, infantry, triggers, teams).
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace TSExt
{
    // One cell of a tile template (from the TMP file of the theater).
    public struct TmpCell
    {
        public bool Present;
        public byte Height;     // height offset inside the template
        public byte Land;       // terrain type: 0 clear, 7/8 rock, 9 water, 10 beach, 11/12 road, 13 clear, 14 rough, 15 cliff, 1-4 ice, 5 tunnel, 6 rail
        public byte Ramp;       // 0 = flat
    }

    public sealed class TileTemplate
    {
        public int Width, Height;
        public TmpCell[] Cells;
        public string File;
        public int Set;
    }

    public sealed class Theater
    {
        public string Name;
        public IniFile Ini;
        public readonly List<string> SetNames = new List<string>();
        public readonly List<string> SetFiles = new List<string>();
        public readonly List<int> SetStart = new List<int>();
        public TileTemplate[] Tiles;
        public string Extension;

        public static Theater Load(GameFiles fs, string theaterName)
        {
            Theater t = new Theater();
            t.Name = theaterName.ToUpperInvariant();
            string iniName = t.Name == "SNOW" ? "SNOW.INI" : "TEMPERAT.INI";
            t.Extension = t.Name == "SNOW" ? ".sno" : ".tem";
            t.Ini = IniFile.Parse(fs.Read(iniName));
            List<TileTemplate> tiles = new List<TileTemplate>();
            for (int i = 0; i < 1000; i++)
            {
                IniSection s = t.Ini[string.Format("TileSet{0:0000}", i)];
                if (s == null) break;
                int n = 0;
                int.TryParse(s.Get("TilesInSet") ?? "0", out n);
                string file = s.Get("FileName") ?? "";
                t.SetNames.Add(s.Get("SetName") ?? "");
                t.SetFiles.Add(file);
                t.SetStart.Add(tiles.Count);
                for (int k = 1; k <= n; k++)
                {
                    string fn = string.Format("{0}{1:00}{2}", file, k, t.Extension);
                    TileTemplate tt = null;
                    byte[] b = fs.Read(fn);
                    if (b != null) { try { tt = ParseTmp(b); } catch { tt = null; } }
                    if (tt == null) { tt = new TileTemplate(); tt.Width = 1; tt.Height = 1; tt.Cells = new TmpCell[1]; }
                    tt.File = fn; tt.Set = i;
                    tiles.Add(tt);
                }
            }
            t.Tiles = tiles.ToArray();
            return t;
        }

        public static TileTemplate ParseTmp(byte[] b)
        {
            TileTemplate t = new TileTemplate();
            t.Width = BitConverter.ToInt32(b, 0);
            t.Height = BitConverter.ToInt32(b, 4);
            int n = t.Width * t.Height;
            if (n <= 0 || n > 400) throw new InvalidDataException("bad tmp");
            t.Cells = new TmpCell[n];
            for (int i = 0; i < n; i++)
            {
                int off = BitConverter.ToInt32(b, 16 + 4 * i);
                if (off == 0 || off + 52 > b.Length) continue;
                TmpCell c = new TmpCell();
                c.Present = true;
                c.Height = b[off + 40];
                c.Land = b[off + 41];
                c.Ramp = b[off + 42];
                t.Cells[i] = c;
            }
            return t;
        }

        public int SetOf(int tile)
        {
            if (tile < 0 || tile >= Tiles.Length) return 0;
            return Tiles[tile].Set;
        }

        public TmpCell CellOf(int tile, int sub)
        {
            if (tile < 0 || tile >= Tiles.Length) tile = 0;
            TileTemplate t = Tiles[tile];
            if (sub < 0 || sub >= t.Cells.Length) return t.Cells.Length > 0 ? t.Cells[0] : new TmpCell();
            return t.Cells[sub];
        }

        public int TileIndex(string generalKey, int offset)
        {
            string v = Ini.Get("General", generalKey);
            int set;
            if (v == null || !int.TryParse(v, out set) || set >= SetStart.Count) return -1;
            return SetStart[set] + offset;
        }
    }

    public sealed class MapCell
    {
        public int X, Y;
        public int Tile;       // 0xFFFF in the file = clear (0)
        public byte Sub;
        public byte Level;
        public byte Ice;
    }

    // A map file (INI with packed sections).
    public sealed class MapFile
    {
        public IniFile Ini;
        public int Width, Height;               // [Map] Size w,h
        public int[] LocalSize = new int[4];
        public string TheaterName;
        public readonly List<MapCell> Cells = new List<MapCell>();
        public readonly Dictionary<int, MapCell> CellAt = new Dictionary<int, MapCell>();
        public byte[] Overlay;                  // 512*512, 0xFF = none; index = Y * 512 + X
        public byte[] OverlayData;
        public byte[] IsoTail;                  // trailing bytes of IsoMapPack5

        public static int Key(int x, int y) { return (y << 10) | x; }

        public static MapFile Load(byte[] bytes)
        {
            MapFile m = new MapFile();
            m.Ini = IniFile.Parse(bytes);
            string[] size = (m.Ini.Get("Map", "Size") ?? "0,0,0,0").Split(',');
            m.Width = int.Parse(size[2].Trim()); m.Height = int.Parse(size[3].Trim());
            string[] ls = (m.Ini.Get("Map", "LocalSize") ?? "0,0,0,0").Split(',');
            for (int i = 0; i < 4; i++) m.LocalSize[i] = int.Parse(ls[i].Trim());
            m.TheaterName = (m.Ini.Get("Map", "Theater") ?? "TEMPERATE").ToUpperInvariant();
            byte[] iso = Pack.Decode(Pack.FromSection(m.Ini["IsoMapPack5"]), true, 0);
            int count = iso.Length / 11;
            for (int i = 0; i < count; i++)
            {
                int o = i * 11;
                MapCell c = new MapCell();
                c.X = BitConverter.ToUInt16(iso, o);
                c.Y = BitConverter.ToUInt16(iso, o + 2);
                c.Tile = BitConverter.ToInt32(iso, o + 4);
                if (c.Tile == 0xFFFF || c.Tile < 0) c.Tile = 0;
                c.Sub = iso[o + 8]; c.Level = iso[o + 9]; c.Ice = iso[o + 10];
                if (c.X == 0 && c.Y == 0) continue;
                m.Cells.Add(c);
                m.CellAt[Key(c.X, c.Y)] = c;
            }
            int tail = iso.Length - count * 11;
            m.IsoTail = new byte[tail];
            Array.Copy(iso, count * 11, m.IsoTail, 0, tail);
            m.Overlay = m.Ini["OverlayPack"] != null ? Pack.Decode(Pack.FromSection(m.Ini["OverlayPack"]), false, 262144) : null;
            m.OverlayData = m.Ini["OverlayDataPack"] != null ? Pack.Decode(Pack.FromSection(m.Ini["OverlayDataPack"]), false, 262144) : null;
            if (m.Overlay == null || m.Overlay.Length < 262144) { m.Overlay = new byte[262144]; for (int i = 0; i < m.Overlay.Length; i++) m.Overlay[i] = 0xFF; }
            if (m.OverlayData == null || m.OverlayData.Length < 262144) m.OverlayData = new byte[262144];
            return m;
        }

        public MapCell Get(int x, int y)
        {
            MapCell c;
            return CellAt.TryGetValue(Key(x, y), out c) ? c : null;
        }

        public byte OverlayAt(int x, int y) { return (x < 0 || y < 0 || x >= 512 || y >= 512) ? (byte)0xFF : Overlay[y * 512 + x]; }

        public void SetOverlay(int x, int y, byte type, byte data)
        {
            if (x < 0 || y < 0 || x >= 512 || y >= 512) return;
            Overlay[y * 512 + x] = type; OverlayData[y * 512 + x] = data;
        }

        public byte[] Save()
        {
            MemoryStream iso = new MemoryStream();
            foreach (MapCell c in Cells)
            {
                iso.Write(BitConverter.GetBytes((ushort)c.X), 0, 2);
                iso.Write(BitConverter.GetBytes((ushort)c.Y), 0, 2);
                iso.Write(BitConverter.GetBytes(c.Tile == 0 ? 0xFFFF : c.Tile), 0, 4);
                iso.WriteByte(c.Sub); iso.WriteByte(c.Level); iso.WriteByte(c.Ice);
            }
            if (IsoTail != null) iso.Write(IsoTail, 0, IsoTail.Length);
            Pack.ToSection(Ini.GetOrAdd("IsoMapPack5"), Pack.Encode(iso.ToArray(), true, 8184));
            Pack.ToSection(Ini.GetOrAdd("OverlayPack"), Pack.Encode(Overlay, false, 8192));
            Pack.ToSection(Ini.GetOrAdd("OverlayDataPack"), Pack.Encode(OverlayData, false, 8192));
            Ini.Set("Map", "Size", string.Format("0,0,{0},{1}", Width, Height));
            Ini.Set("Map", "LocalSize", string.Format("{0},{1},{2},{3}", LocalSize[0], LocalSize[1], LocalSize[2], LocalSize[3]));
            return Ini.ToBytes();
        }

        // Waypoint / cell number: Y * 1000 + X ("tested against the official maps", see FINDINGS.md)
        public static int CellNumber(int x, int y) { return y * 1000 + x; }
        public static void FromCellNumber(int n, out int x, out int y) { y = n / 1000; x = n % 1000; }

        public List<KeyValuePair<int, int>> Waypoints()
        {
            List<KeyValuePair<int, int>> r = new List<KeyValuePair<int, int>>();
            IniSection s = Ini["Waypoints"];
            if (s == null) return r;
            foreach (KeyValuePair<string, string> kv in s.Pairs)
            {
                int k, v;
                if (int.TryParse(kv.Key, out k) && int.TryParse(kv.Value, out v)) r.Add(new KeyValuePair<int, int>(k, v));
            }
            return r;
        }
    }

    // Which cells are free and flat (for placing buildings and units).
    public sealed class Placement
    {
        readonly MapFile map;
        readonly Theater th;
        readonly HashSet<int> blocked = new HashSet<int>();

        public Placement(MapFile m, Theater t)
        {
            map = m; th = t;
            // trees and other terrain objects
            IniSection ter = m.Ini["Terrain"];
            if (ter != null)
                foreach (KeyValuePair<string, string> kv in ter.Pairs)
                {
                    int n; if (!int.TryParse(kv.Key, out n)) continue;
                    int x, y; MapFile.FromCellNumber(n, out x, out y);
                    Block(x, y);
                }
            // existing structures (rough: their anchor cell and a 3x3 area)
            IniSection st = m.Ini["Structures"];
            if (st != null)
                foreach (KeyValuePair<string, string> kv in st.Pairs)
                {
                    string[] f = kv.Value.Split(',');
                    if (f.Length < 5) continue;
                    int x, y;
                    if (!int.TryParse(f[3], out x) || !int.TryParse(f[4], out y)) continue;
                    for (int dx = 0; dx < 3; dx++) for (int dy = 0; dy < 3; dy++) Block(x + dx, y + dy);
                }
        }

        public void Block(int x, int y) { blocked.Add(MapFile.Key(x, y)); }
        public bool IsBlocked(int x, int y) { return blocked.Contains(MapFile.Key(x, y)); }

        public bool InLocal(int x, int y)
        {
            // Visible area check via the screen position of the cell (iso layout).
            int sx = x - y + map.Width;  // 0 .. 2*W
            int sy = x + y - map.Width;  // 0 .. 2*H
            int l = map.LocalSize[0], t = map.LocalSize[1], w = map.LocalSize[2], h = map.LocalSize[3];
            return sx >= 2 * l + 2 && sx <= 2 * (l + w) - 2 && sy >= 2 * t + 4 && sy <= 2 * (t + h) - 2;
        }

        // Flat, buildable ground without overlay and without objects. Returns -1 if not buildable, else the height.
        public int BuildableLevel(int x, int y)
        {
            MapCell c = map.Get(x, y);
            if (c == null || IsBlocked(x, y) || !InLocal(x, y)) return -1;
            if (map.OverlayAt(x, y) != 0xFF) return -1;
            TmpCell tc = th.CellOf(c.Tile, c.Sub);
            if (tc.Ramp != 0) return -1;
            switch (tc.Land)
            {
                case 0: case 11: case 12: case 13: case 14: break;
                default: return -1;
            }
            return c.Level;
        }

        public bool Passable(int x, int y)
        {
            MapCell c = map.Get(x, y);
            if (c == null || IsBlocked(x, y) || !InLocal(x, y)) return false;
            TmpCell tc = th.CellOf(c.Tile, c.Sub);
            switch (tc.Land) { case 7: case 8: case 9: case 15: return false; }
            return true;
        }

        // A free w x h area with the same height (plus a free margin) around (x,y), its top cell nearest to (cx,cy).
        public bool CanPlace(int x, int y, int w, int h, int margin)
        {
            int lvl = BuildableLevel(x, y);
            if (lvl < 0) return false;
            for (int dx = -margin; dx < w + margin; dx++)
                for (int dy = -margin; dy < h + margin; dy++)
                {
                    bool inner = dx >= 0 && dy >= 0 && dx < w && dy < h;
                    if (inner) { if (BuildableLevel(x + dx, y + dy) != lvl) return false; }
                    else if (!Passable(x + dx, y + dy)) return false;
                }
            return true;
        }

        public bool FindSpot(int cx, int cy, int w, int h, int margin, int maxRadius, out int fx, out int fy)
        {
            for (int r = 0; r <= maxRadius; r++)
            {
                for (int dx = -r; dx <= r; dx++)
                    for (int dy = -r; dy <= r; dy++)
                    {
                        if (Math.Max(Math.Abs(dx), Math.Abs(dy)) != r) continue;
                        int x = cx + dx, y = cy + dy;
                        if (CanPlace(x, y, w, h, margin)) { fx = x; fy = y; return true; }
                    }
            }
            fx = fy = -1;
            return false;
        }

        public void Occupy(int x, int y, int w, int h)
        {
            for (int dx = 0; dx < w; dx++) for (int dy = 0; dy < h; dy++) Block(x + dx, y + dy);
        }

        public bool FindFreeCell(int cx, int cy, int maxRadius, out int fx, out int fy)
        {
            for (int r = 0; r <= maxRadius; r++)
                for (int dx = -r; dx <= r; dx++)
                    for (int dy = -r; dy <= r; dy++)
                    {
                        if (Math.Max(Math.Abs(dx), Math.Abs(dy)) != r) continue;
                        int x = cx + dx, y = cy + dy;
                        if (Passable(x, y) && map.OverlayAt(x, y) == 0xFF) { fx = x; fy = y; return true; }
                    }
            fx = fy = -1;
            return false;
        }
    }

    // Builds the mission sections of a map: houses, objects, triggers, teams.
    public sealed class MissionBuilder
    {
        public readonly MapFile Map;
        readonly List<string> houses = new List<string>();
        int structNo, unitNo, infNo, aircraftNo, idNo = 0x0A000000, waypointNo = 0;
        readonly IniSection trig, ev, act, tags, teams, tasks, scripts, structs, units, inf, air, wps, vars;
        readonly Dictionary<string, int> waypointIndex = new Dictionary<string, int>();

        public MissionBuilder(MapFile m)
        {
            Map = m;
            // Old mission logic goes; the objects already on the map (civilian and tech buildings) stay, without tags.
            foreach (string s in new string[] { "TeamTypes", "TaskForces", "ScriptTypes" })
            {
                IniSection list = m.Ini[s];
                if (list != null) foreach (string id in list.Values()) m.Ini.RemoveSection(id);
            }
            foreach (string s in new string[] { "Triggers", "Events", "Actions", "Tags", "TeamTypes", "TaskForces", "ScriptTypes",
                                                "CellTags", "VariableNames", "AITriggerTypes", "AITriggerTypesEnable", "Digest", "Aircraft" })
                m.Ini.RemoveSection(s);
            trig = m.Ini.GetOrAdd("Triggers"); ev = m.Ini.GetOrAdd("Events"); act = m.Ini.GetOrAdd("Actions"); tags = m.Ini.GetOrAdd("Tags");
            teams = m.Ini.GetOrAdd("TeamTypes"); tasks = m.Ini.GetOrAdd("TaskForces"); scripts = m.Ini.GetOrAdd("ScriptTypes");
            structs = m.Ini.GetOrAdd("Structures"); units = m.Ini.GetOrAdd("Units"); inf = m.Ini.GetOrAdd("Infantry"); air = m.Ini.GetOrAdd("Aircraft");
            foreach (IniSection objs in new IniSection[] { structs, units, inf })
            {
                List<KeyValuePair<string, string>> keep = new List<KeyValuePair<string, string>>(objs.Pairs);
                objs.Pairs.Clear();
                int tagField = objs == structs ? 6 : (objs == units ? 7 : 8);
                foreach (KeyValuePair<string, string> kv in keep)
                {
                    string[] f = kv.Value.Split(',');
                    if (f.Length > tagField) f[tagField] = "None";
                    int no = objs == structs ? structNo++ : (objs == units ? unitNo++ : infNo++);
                    objs.Pairs.Add(new KeyValuePair<string, string>(no.ToString(), string.Join(",", f)));
                }
            }
            m.Ini.RemoveSection("Houses");
            vars = m.Ini.GetOrAdd("VariableNames");
            wps = m.Ini.GetOrAdd("Waypoints");
            foreach (KeyValuePair<int, int> w in m.Waypoints()) if (w.Key >= waypointNo && w.Key < 90) waypointNo = w.Key + 1;
        }

        public string NewId() { return (idNo++).ToString("X8"); }

        public int AddHouse(string name, string side, string color, string allies, int credits, int iq, bool player, int techLevel, string edge)
        {
            IniSection h = Map.Ini.GetOrAdd("Houses");
            h.Set(houses.Count.ToString(), name);
            houses.Add(name);
            IniSection s = Map.Ini.GetOrAdd(name);
            s.Pairs.Clear();
            s.Set("IQ", iq.ToString());
            s.Set("Edge", edge);
            s.Set("Color", color);
            s.Set("Allies", allies);
            s.Set("Side", side);
            s.Set("Credits", credits.ToString());
            s.Set("ActsLike", side == "Nod" ? "1" : "0");
            s.Set("TechLevel", techLevel.ToString());
            s.Set("PercentBuilt", "100");
            s.Set("PlayerControl", player ? "yes" : "no");
            s.Set("NodeCount", "0");
            return houses.Count - 1;
        }

        public int HouseIndex(string name) { return houses.IndexOf(name); }

        // Base node: the computer rebuilds this building if it is lost.
        public void AddBaseNode(string house, string type, int x, int y)
        {
            IniSection s = Map.Ini[house];
            int n = int.Parse(s.Get("NodeCount") ?? "0");
            s.Set(n.ToString("000"), string.Format("{0},{1},{2}", type, x, y));
            s.Set("NodeCount", (n + 1).ToString());
        }

        public void AddStructure(string house, string type, int x, int y, int facing, string tag, bool sellable, bool rebuild, string upgrade1)
        {
            structs.Set((structNo++).ToString(), string.Format("{0},{1},256,{2},{3},{4},{5},{6},{7},1,{8},0,{9},None,None,1,1",
                house, type, x, y, facing, (string.IsNullOrEmpty(tag) ? "None" : tag), sellable ? 1 : 0, rebuild ? 1 : 0, upgrade1 != null ? 1 : 0, upgrade1 ?? "None"));
        }

        public void AddUnit(string house, string type, int x, int y, int facing, string mission, string tag, int veterancy)
        {
            units.Set((unitNo++).ToString(), string.Format("{0},{1},256,{2},{3},{4},{5},{6},{7},-1,0,-1,0,0",
                house, type, x, y, facing, mission, (string.IsNullOrEmpty(tag) ? "None" : tag), veterancy));
        }

        public void AddInfantry(string house, string type, int x, int y, int subCell, string mission, string tag, int veterancy)
        {
            inf.Set((infNo++).ToString(), string.Format("{0},{1},256,{2},{3},{4},{5},0,{6},{7},-1,0,0,0",
                house, type, x, y, subCell, mission, (string.IsNullOrEmpty(tag) ? "None" : tag), veterancy));
        }

        public void AddAircraft(string house, string type, int x, int y, int facing, string mission)
        {
            air.Set((aircraftNo++).ToString(), string.Format("{0},{1},256,{2},{3},{4},{5},None,0,-1,0,0",
                house, type, x, y, facing, mission));
        }

        public void AddTerrain(int x, int y, string type) { Map.Ini.GetOrAdd("Terrain").Set(MapFile.CellNumber(x, y).ToString(), type); }

        // Waypoint at a cell; returns its number. Waypoint letters for actions: 0 = A, 25 = Z, 26 = AA ...
        public int AddWaypoint(int x, int y)
        {
            int n = waypointNo++;
            wps.Set(n.ToString(), MapFile.CellNumber(x, y).ToString());
            return n;
        }

        public static string WaypointLetters(int n)
        {
            StringBuilder sb = new StringBuilder();
            n++;
            while (n > 0) { int r = (n - 1) % 26; sb.Insert(0, (char)('A' + r)); n = (n - 1) / 26; }
            return sb.ToString();
        }

        public void SetVariable(int index, string name) { vars.Set(index.ToString(), name + ",0"); }

        public string AddTaskForce(string name, params string[] members)
        {
            string id = NewId();
            tasks.Set(tasks.Pairs.Count.ToString(), id);
            IniSection s = Map.Ini.GetOrAdd(id);
            s.Set("Name", name);
            for (int i = 0; i < members.Length; i++) s.Set(i.ToString(), members[i]);   // "count,TYPE"
            s.Set("Group", "-1");
            return id;
        }

        public string AddScript(string name, params string[] lines)
        {
            string id = NewId();
            scripts.Set(scripts.Pairs.Count.ToString(), id);
            IniSection s = Map.Ini.GetOrAdd(id);
            s.Set("Name", name);
            for (int i = 0; i < lines.Length; i++) s.Set(i.ToString(), lines[i]);      // "action,param"
            return id;
        }

        public string AddTeam(string name, string house, string taskForce, string script, int originWaypoint, int veteran, bool autocreate, int max, int priority)
        {
            string id = NewId();
            teams.Set(teams.Pairs.Count.ToString(), id);
            IniSection s = Map.Ini.GetOrAdd(id);
            s.Set("Name", name); s.Set("VeteranLevel", veteran.ToString()); s.Set("Loadable", "no"); s.Set("Full", "no");
            s.Set("Annoyance", "no"); s.Set("GuardSlower", "no"); s.Set("House", house); s.Set("Recruiter", "no");
            s.Set("Autocreate", autocreate ? "yes" : "no"); s.Set("Prebuild", "no"); s.Set("Reinforce", "no"); s.Set("Droppod", "no");
            s.Set("Whiner", "no"); s.Set("LooseRecruit", "no"); s.Set("Aggressive", "yes"); s.Set("Suicide", "no");
            s.Set("Priority", priority.ToString()); s.Set("Max", max.ToString()); s.Set("TechLevel", "0"); s.Set("Group", "-1");
            s.Set("OnTransOnly", "no"); s.Set("AvoidThreats", "no"); s.Set("IonImmune", "no"); s.Set("TransportsReturnOnUnload", "no");
            s.Set("AreTeamMembersRecruitable", "no"); s.Set("IsBaseDefense", "no"); s.Set("OnlyTargetHouseEnemy", "no");
            s.Set("Waypoint", WaypointLetters(originWaypoint)); s.Set("Script", script); s.Set("TaskForce", taskForce);
            return id;
        }

        // events: "type,0,param" each; actions: "type,p1,p2,0,0,0,0,WP" each. repeat: 0 once, 2 repeating.
        public string AddTrigger(string name, string house, int repeat, string[] events, string[] actions)
        {
            return AddTrigger(name, house, repeat, events, actions, false);
        }

        public string AddTrigger(string name, string house, int repeat, string[] events, string[] actions, bool disabled)
        {
            return AddTriggerFlags(name, house, repeat, events, actions, disabled, true, true, true);
        }

        // A trigger that is active on one difficulty only (0 = easy, 1 = normal, 2 = hard).
        public string AddTriggerDiff(string name, string house, int repeat, string[] events, string[] actions, int difficulty)
        {
            return AddTriggerFlags(name, house, repeat, events, actions, false, difficulty == 0, difficulty == 1, difficulty == 2);
        }

        readonly Dictionary<string, string> tagOfTrigger = new Dictionary<string, string>();

        public string AddTriggerFlags(string name, string house, int repeat, string[] events, string[] actions, bool disabled, bool easy, bool normal, bool hard)
        {
            string id = NewId();
            trig.Set(id, string.Format("{0},<none>,{1},{2},{3},{4},{5},{6}", house, name, disabled ? 1 : 0, easy ? 1 : 0, normal ? 1 : 0, hard ? 1 : 0, repeat == 2 ? 1 : 0));
            ev.Set(id, events.Length + "," + string.Join(",", events));
            act.Set(id, actions.Length + "," + string.Join(",", actions));
            string tagId = NewId();
            tags.Set(tagId, string.Format("{0},{1},{2}", repeat, name, id));
            tagOfTrigger[id] = tagId;
            return id;
        }

        public string TagOf(string triggerId) { string t; return tagOfTrigger.TryGetValue(triggerId, out t) ? t : null; }

        // Attaches a tag to a structure (position in [Structures]), for "destroyed" events.
        public void AttachTag(int structureIndex, string tagId)
        {
            KeyValuePair<string, string> kv = structs.Pairs[structureIndex];
            string[] f = kv.Value.Split(',');
            f[6] = tagId;
            structs.Pairs[structureIndex] = new KeyValuePair<string, string>(kv.Key, string.Join(",", f));
        }

        public static string Ev(int type, int param) { return string.Format("{0},0,{1}", type, param); }
        public static string Act(int type, int param) { return string.Format("{0},0,{1},0,0,0,0,A", type, param); }
        public static string ActTeam(int type, string teamId) { return string.Format("{0},1,{1},0,0,0,0,A", type, teamId); }
        public static string ActTeamAt(int type, string teamId, int waypoint) { return string.Format("{0},1,{1},0,0,0,0,{2}", type, teamId, WaypointLetters(waypoint)); }
        public static string ActWp(int type, int param, int waypoint) { return string.Format("{0},0,{1},0,0,0,0,{2}", type, param, WaypointLetters(waypoint)); }
        public static string ActText(int type, string label) { return string.Format("{0},4,{1},0,0,0,0,A", type, label); }
    }
}
