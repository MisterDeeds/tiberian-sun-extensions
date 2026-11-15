// Tiberian Sun Extensions - core library (C# 5, compiled at run time by Windows PowerShell's Add-Type).
// Reads the game's own files from the local installation: MIX archives (with the encrypted header of
// Tiberian Sun), INI files, and the packed map sections (LZO "format 5" and LCW "format 80").
// Nothing from the game is shipped with this project; everything is read from the player's installation.
using System;
using System.Collections.Generic;
using System.IO;
using System.Numerics;
using System.Text;

namespace TSExt
{
    // ------------------------------------------------------------------------------------------------
    // Blowfish (standard, ECB, big-endian words). The initial P-array and S-boxes are the hexadecimal
    // digits of pi; they are computed here instead of being typed in as a table.
    // ------------------------------------------------------------------------------------------------
    public sealed class Blowfish
    {
        static uint[] piWords;
        readonly uint[] p = new uint[18];
        readonly uint[,] s = new uint[4, 256];

        static uint[] PiWords()
        {
            if (piWords != null) return piWords;
            const int words = 18 + 4 * 256;
            int bits = words * 32 + 64;
            BigInteger one = BigInteger.One << bits;
            // Machin: pi = 16 atan(1/5) - 4 atan(1/239)
            BigInteger pi = 16 * ArcTanInv(5, one) - 4 * ArcTanInv(239, one);
            BigInteger frac = pi - 3 * one; // fractional part, scaled by 2^bits
            frac >>= 64;                    // drop the guard bits
            uint[] w = new uint[words];
            for (int i = words - 1; i >= 0; i--)
            {
                w[i] = (uint)(frac & 0xFFFFFFFF);
                frac >>= 32;
            }
            piWords = w;
            return w;
        }

        static BigInteger ArcTanInv(int x, BigInteger one)
        {
            BigInteger xsq = x * x;
            BigInteger term = one / x;
            BigInteger sum = term;
            int n = 1;
            bool neg = true;
            while (!term.IsZero)
            {
                term /= xsq;
                n += 2;
                BigInteger t = term / n;
                if (t.IsZero) break;
                sum = neg ? sum - t : sum + t;
                neg = !neg;
            }
            return sum;
        }

        public Blowfish(byte[] key)
        {
            uint[] w = PiWords();
            for (int i = 0; i < 18; i++) p[i] = w[i];
            for (int b = 0; b < 4; b++)
                for (int i = 0; i < 256; i++) s[b, i] = w[18 + b * 256 + i];
            int k = 0;
            for (int i = 0; i < 18; i++)
            {
                uint d = 0;
                for (int j = 0; j < 4; j++) { d = (d << 8) | key[k]; k = (k + 1) % key.Length; }
                p[i] ^= d;
            }
            uint l = 0, r = 0;
            for (int i = 0; i < 18; i += 2) { Encipher(ref l, ref r); p[i] = l; p[i + 1] = r; }
            for (int b = 0; b < 4; b++)
                for (int i = 0; i < 256; i += 2) { Encipher(ref l, ref r); s[b, i] = l; s[b, i + 1] = r; }
        }

        public static uint Check() { return PiWords()[0]; }

        uint F(uint x)
        {
            return ((s[0, x >> 24] + s[1, (x >> 16) & 0xFF]) ^ s[2, (x >> 8) & 0xFF]) + s[3, x & 0xFF];
        }

        void Encipher(ref uint l, ref uint r)
        {
            for (int i = 0; i < 16; i++) { l ^= p[i]; r ^= F(l); uint t = l; l = r; r = t; }
            uint t2 = l; l = r; r = t2;
            r ^= p[16]; l ^= p[17];
        }

        void Decipher(ref uint l, ref uint r)
        {
            for (int i = 17; i > 1; i--) { l ^= p[i]; r ^= F(l); uint t = l; l = r; r = t; }
            uint t2 = l; l = r; r = t2;
            r ^= p[1]; l ^= p[0];
        }

        public void DecryptInPlace(byte[] data, int offset, int length)
        {
            for (int i = offset; i + 8 <= offset + length; i += 8)
            {
                // Standard Blowfish: big-endian halves.
                uint l = (uint)(data[i] << 24 | data[i + 1] << 16 | data[i + 2] << 8 | data[i + 3]);
                uint r = (uint)(data[i + 4] << 24 | data[i + 5] << 16 | data[i + 6] << 8 | data[i + 7]);
                Decipher(ref l, ref r);
                data[i] = (byte)(l >> 24); data[i + 1] = (byte)(l >> 16); data[i + 2] = (byte)(l >> 8); data[i + 3] = (byte)l;
                data[i + 4] = (byte)(r >> 24); data[i + 5] = (byte)(r >> 16); data[i + 6] = (byte)(r >> 8); data[i + 7] = (byte)r;
            }
        }
    }

    // ------------------------------------------------------------------------------------------------
    // MIX archives
    // ------------------------------------------------------------------------------------------------
    public sealed class MixEntry
    {
        public uint Id;
        public uint Offset;
        public uint Size;
    }

    public sealed class MixFile
    {
        // Westwood's public key, used to decrypt the Blowfish key of an encrypted MIX header.
        const string PublicKey = "AihRvNoIbTn85FZRYNZRcT+i6KpU+maCsEqr3Q5q+LDB5tH7Tz2qQ38V";

        public string Name;
        public readonly Dictionary<uint, MixEntry> Entries = new Dictionary<uint, MixEntry>();
        public bool Encrypted;
        readonly string path;      // either a file on disk ...
        readonly byte[] data;      // ... or bytes in memory (a MIX inside a MIX)
        readonly long baseOffset;  // offset of the MIX inside the file on disk
        long bodyOffset;

        public MixFile(string filePath) : this(filePath, 0, new FileInfo(filePath).Length) { }

        public MixFile(string filePath, long offset, long length)
        {
            path = filePath; baseOffset = offset; Name = Path.GetFileName(filePath);
            byte[] head = ReadDisk(0, (int)Math.Min(length, 4 + 80 + 8));
            ParseHeader(head, length, true);
        }

        public MixFile(byte[] bytes, string name)
        {
            data = bytes; Name = name;
            ParseHeader(bytes, bytes.Length, false);
        }

        byte[] ReadDisk(long off, int len)
        {
            using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            {
                fs.Position = baseOffset + off;
                byte[] b = new byte[len];
                int got = 0;
                while (got < len) { int n = fs.Read(b, got, len - got); if (n <= 0) break; got += n; }
                return b;
            }
        }

        byte[] ReadRaw(long off, int len)
        {
            if (data != null) { byte[] b = new byte[len]; Array.Copy(data, off, b, 0, len); return b; }
            return ReadDisk(off, len);
        }

        void ParseHeader(byte[] head, long length, bool disk)
        {
            ushort first = BitConverter.ToUInt16(head, 0);
            if (first != 0)
            {
                // Old format (Tiberian Dawn): count, size, entries.
                int count = first;
                byte[] idx = ReadRaw(6, count * 12);
                ReadIndex(idx, 0, count);
                bodyOffset = 6 + count * 12;
                return;
            }
            uint flags = BitConverter.ToUInt32(head, 0);
            Encrypted = (flags & 0x20000) != 0;
            if (!Encrypted)
            {
                byte[] h = ReadRaw(4, 6);
                int count = BitConverter.ToUInt16(h, 0);
                byte[] idx = ReadRaw(10, count * 12);
                ReadIndex(idx, 0, count);
                bodyOffset = 10 + count * 12;
                return;
            }
            byte[] keySource = ReadRaw(4, 80);
            byte[] key = DecryptKey(keySource);
            Blowfish bf = new Blowfish(key);
            byte[] block = ReadRaw(84, 8);
            bf.DecryptInPlace(block, 0, 8);
            int n = BitConverter.ToUInt16(block, 0);
            int headerLen = 6 + n * 12;
            int encLen = (headerLen + 7) & ~7;
            byte[] enc = ReadRaw(84, encLen);
            bf.DecryptInPlace(enc, 0, encLen);
            ReadIndex(enc, 6, n);
            bodyOffset = 84 + encLen;
        }

        void ReadIndex(byte[] b, int off, int count)
        {
            for (int i = 0; i < count; i++)
            {
                MixEntry e = new MixEntry();
                e.Id = BitConverter.ToUInt32(b, off + i * 12);
                e.Offset = BitConverter.ToUInt32(b, off + i * 12 + 4);
                e.Size = BitConverter.ToUInt32(b, off + i * 12 + 8);
                Entries[e.Id] = e;
            }
        }

        static byte[] DecryptKey(byte[] src)
        {
            byte[] der = Convert.FromBase64String(PublicKey);
            // DER INTEGER: 0x02, length, big-endian bytes
            int len = der[1];
            byte[] mod = new byte[len + 1];               // little-endian + sign byte for BigInteger
            for (int i = 0; i < len; i++) mod[i] = der[2 + len - 1 - i];
            BigInteger n = new BigInteger(mod);
            BigInteger e = new BigInteger(0x10001);
            int bitLen = 0;
            for (BigInteger t = n; !t.IsZero; t >>= 1) bitLen++;
            int a = (bitLen - 2) / 8;                      // XCC: len = bitlen - 1; a = (len - 1) / 8
            List<byte> outp = new List<byte>();
            int pos = 0;
            while (pos + a + 1 <= src.Length)
            {
                byte[] blk = new byte[a + 2];
                Array.Copy(src, pos, blk, 0, a + 1);       // little-endian, last byte 0 keeps it positive
                BigInteger c = new BigInteger(blk);
                BigInteger m = BigInteger.ModPow(c, e, n);
                byte[] mb = m.ToByteArray();
                for (int i = 0; i < a; i++) outp.Add(i < mb.Length ? mb[i] : (byte)0);
                pos += a + 1;
            }
            byte[] key = new byte[56];
            for (int i = 0; i < 56 && i < outp.Count; i++) key[i] = outp[i];
            return key;
        }

        // File name -> id, as Tiberian Sun computes it (CRC-32 of the upper-case name, padded).
        public static uint TsId(string name)
        {
            string u = name.ToUpperInvariant();
            byte[] b = Encoding.ASCII.GetBytes(u);
            int l = b.Length, a = l >> 2 << 2;
            List<byte> buf = new List<byte>(b);
            if ((l & 3) != 0)
            {
                buf.Add((byte)(l - a));
                int i = 3 - (l & 3);
                while (i-- > 0) buf.Add(b[a]);
            }
            return Crc32(buf.ToArray());
        }

        static uint[] crcTable;
        public static uint Crc32(byte[] b)
        {
            if (crcTable == null)
            {
                crcTable = new uint[256];
                for (uint i = 0; i < 256; i++)
                {
                    uint c = i;
                    for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
                    crcTable[i] = c;
                }
            }
            uint crc = 0xFFFFFFFF;
            foreach (byte x in b) crc = crcTable[(crc ^ x) & 0xFF] ^ (crc >> 8);
            return crc ^ 0xFFFFFFFF;
        }

        public bool Contains(string name) { return Entries.ContainsKey(TsId(name)); }

        public MixEntry Find(string name)
        {
            MixEntry e;
            return Entries.TryGetValue(TsId(name), out e) ? e : null;
        }

        public byte[] Read(MixEntry e) { return ReadRaw(bodyOffset + e.Offset, (int)e.Size); }

        public byte[] Read(string name)
        {
            MixEntry e = Find(name);
            return e == null ? null : Read(e);
        }

        // A MIX inside this MIX. On disk it is read in place (no copy of big archives).
        public MixFile OpenNested(string name)
        {
            MixEntry e = Find(name);
            if (e == null) return null;
            if (data != null) { MixFile m = new MixFile(Read(e), name); return m; }
            MixFile n = new MixFile(path, baseOffset + bodyOffset + e.Offset, e.Size);
            n.Name = name;
            return n;
        }
    }

    // Writes an unencrypted MIX archive (new format, no checksum). The game finds files by binary search over the
    // index, which is sorted by id as signed 32-bit numbers.
    public static class MixWriter
    {
        public static byte[] Build(IList<KeyValuePair<string, byte[]>> files)
        {
            List<KeyValuePair<uint, byte[]>> list = new List<KeyValuePair<uint, byte[]>>();
            foreach (KeyValuePair<string, byte[]> f in files) list.Add(new KeyValuePair<uint, byte[]>(MixFile.TsId(f.Key), f.Value));
            list.Sort(delegate(KeyValuePair<uint, byte[]> a, KeyValuePair<uint, byte[]> b) { return ((int)a.Key).CompareTo((int)b.Key); });
            MemoryStream body = new MemoryStream();
            MemoryStream o = new MemoryStream();
            BinaryWriter w = new BinaryWriter(o);
            uint bodySize = 0;
            foreach (KeyValuePair<uint, byte[]> f in list) bodySize += (uint)f.Value.Length;
            w.Write((uint)0);                 // flags: not encrypted, no checksum
            w.Write((ushort)list.Count);
            w.Write(bodySize);
            uint off = 0;
            foreach (KeyValuePair<uint, byte[]> f in list)
            {
                w.Write(f.Key); w.Write(off); w.Write((uint)f.Value.Length);
                off += (uint)f.Value.Length;
            }
            foreach (KeyValuePair<uint, byte[]> f in list) w.Write(f.Value);
            w.Flush();
            return o.ToArray();
        }
    }

    // A set of MIX files searched in order (the first one that has a file wins), plus loose files in
    // the game folder, which the game prefers over every MIX.
    public sealed class GameFiles
    {
        public readonly string GameDir;
        public readonly List<MixFile> Mixes = new List<MixFile>();
        public bool UseLooseFiles = true;

        public GameFiles(string gameDir) { GameDir = gameDir; }

        public void Add(MixFile m) { if (m != null) Mixes.Add(m); }

        public MixFile AddFile(string fileName)
        {
            string p = Path.Combine(GameDir, fileName);
            if (!File.Exists(p))
            {
                // case-insensitive lookup
                foreach (string f in Directory.GetFiles(GameDir))
                    if (string.Equals(Path.GetFileName(f), fileName, StringComparison.OrdinalIgnoreCase)) { p = f; break; }
            }
            if (File.Exists(p)) { MixFile m = new MixFile(p); Mixes.Add(m); return m; }
            foreach (MixFile parent in Mixes.ToArray())
            {
                if (parent.Contains(fileName)) { MixFile n = parent.OpenNested(fileName); Mixes.Add(n); return n; }
            }
            return null;
        }

        // Opens every copy of a nested MIX (e.g. ISOTEMP.MIX exists in EXPAND01.MIX and TIBSUN.MIX), in search order.
        public int AddNestedAll(string fileName)
        {
            int n = 0;
            foreach (MixFile parent in Mixes.ToArray())
            {
                if (!parent.Contains(fileName)) continue;
                MixFile m = parent.OpenNested(fileName);
                if (m != null) { m.Name = parent.Name + "/" + fileName; Mixes.Add(m); n++; }
            }
            return n;
        }

        public string Where(string name)
        {
            if (UseLooseFiles && File.Exists(Path.Combine(GameDir, name))) return "(loose)";
            foreach (MixFile m in Mixes) if (m.Contains(name)) return m.Name;
            return null;
        }

        public byte[] Read(string name)
        {
            string loose = Path.Combine(GameDir, name);
            if (UseLooseFiles && File.Exists(loose)) return File.ReadAllBytes(loose);
            foreach (MixFile m in Mixes) { byte[] b = m.Read(name); if (b != null) return b; }
            return null;
        }

        public List<string> WhereAll(string name)
        {
            List<string> r = new List<string>();
            foreach (MixFile m in Mixes) if (m.Contains(name)) r.Add(m.Name);
            return r;
        }

        public byte[] ReadFrom(string mixName, string name)
        {
            foreach (MixFile m in Mixes) if (string.Equals(m.Name, mixName, StringComparison.OrdinalIgnoreCase)) return m.Read(name);
            return null;
        }
    }

    // ------------------------------------------------------------------------------------------------
    // Compression used in map files
    // ------------------------------------------------------------------------------------------------
    public static class Lzo
    {
        public static byte[] Decompress(byte[] src, int srcOff, int srcLen, int outLen)
        {
            byte[] o = new byte[outLen];
            int ip = srcOff, op = 0, end = srcOff + srcLen;
            int t, mpos;
            int state = 0; // 0 = loop start, 1 = first literal run, 2 = match, 3 = match_next
            if (src[ip] > 17)
            {
                t = src[ip++] - 17;
                if (t < 4) { state = 3; }
                else { Array.Copy(src, ip, o, op, t); ip += t; op += t; state = 1; }
            }
            else t = 0;
            while (true)
            {
                if (state == 0)
                {
                    t = src[ip++];
                    if (t >= 16) { state = 2; continue; }
                    if (t == 0) { while (src[ip] == 0) { t += 255; ip++; } t += 15 + src[ip++]; }
                    t += 3;
                    Array.Copy(src, ip, o, op, t); ip += t; op += t;
                    state = 1;
                    continue;
                }
                if (state == 1)
                {
                    t = src[ip++];
                    if (t >= 16) { state = 2; continue; }
                    mpos = op - (1 + 0x0800) - (t >> 2) - (src[ip++] << 2);
                    o[op++] = o[mpos++]; o[op++] = o[mpos++]; o[op++] = o[mpos++];
                    // match_done
                    t = src[ip - 2] & 3;
                    if (t == 0) { state = 0; continue; }
                    state = 3; continue;
                }
                if (state == 3)
                {
                    // copy t (1..3) literals, then the next instruction is a match
                    while (t-- > 0) o[op++] = src[ip++];
                    t = src[ip++];
                    state = 2; continue;
                }
                // state 2: match
                if (t >= 64)
                {
                    mpos = op - 1 - ((t >> 2) & 7) - (src[ip++] << 3);
                    t = (t >> 5) - 1;
                }
                else if (t >= 32)
                {
                    t &= 31;
                    if (t == 0) { while (src[ip] == 0) { t += 255; ip++; } t += 31 + src[ip++]; }
                    mpos = op - 1 - ((src[ip] >> 2) + (src[ip + 1] << 6));
                    ip += 2;
                }
                else if (t >= 16)
                {
                    mpos = op - ((t & 8) << 11);
                    t &= 7;
                    if (t == 0) { while (src[ip] == 0) { t += 255; ip++; } t += 7 + src[ip++]; }
                    mpos -= (src[ip] >> 2) + (src[ip + 1] << 6);
                    ip += 2;
                    if (mpos == op) break; // end of stream
                    mpos -= 0x4000;
                }
                else
                {
                    mpos = op - 1 - (t >> 2) - (src[ip++] << 2);
                    o[op++] = o[mpos++]; o[op++] = o[mpos++];
                    t = src[ip - 2] & 3;
                    if (t == 0) { state = 0; continue; }
                    state = 3; continue;
                }
                // copy t + 2 bytes (may overlap)
                o[op++] = o[mpos++]; o[op++] = o[mpos++];
                while (t-- > 0) o[op++] = o[mpos++];
                t = src[ip - 2] & 3;
                if (t == 0) { state = 0; continue; }
                state = 3;
            }
            if (op != outLen) throw new InvalidDataException("LZO: got " + op + " bytes, expected " + outLen);
            return o;
        }

        // LZO1X stream with greedy matching (M2/M3/M4 matches), readable by the game's lzo1x_decompress.
        public static byte[] Compress(byte[] src)
        {
            MemoryStream o = new MemoryStream();
            int n = src.Length;
            int[] head = new int[1 << 14];
            for (int i = 0; i < head.Length; i++) head[i] = -1;
            int ip = 0, lit = 0; // lit = start of pending literals
            bool first = true;
            while (ip + 3 < n)
            {
                uint hv = (uint)((src[ip] << 10) ^ (src[ip + 1] << 5) ^ src[ip + 2]) * 2654435761u;
                int h = (int)(hv >> 18);
                int cand = head[h];
                head[h] = ip;
                int dist = ip - cand;
                int len = 0;
                if (cand >= 0 && dist > 0 && dist <= 0xBFFF)
                {
                    while (ip + len < n && src[cand + len] == src[ip + len] && len < 264) len++;
                }
                // Literal runs of 1..3 bytes after a match need a match of length >= 3 when the
                // previous instruction was a literal run; keep it simple: require len >= 4, or 3 with short distance.
                bool ok = len >= 4 || (len == 3 && dist <= 0x0800);
                if (!ok) { ip++; continue; }
                int litLen = ip - lit;
                if (first && litLen == 0)
                {
                    // the very first instruction must be a literal run: emit the first byte as literal
                    ip++; continue;
                }
                EmitLiterals(o, src, lit, litLen, first);
                first = false;
                EmitMatch(o, dist, len);
                ip += len;
                lit = ip;
            }
            int rest = n - lit;
            if (rest > 0) EmitLiterals(o, src, lit, rest, first);
            // end marker: M4 match with distance 0
            o.WriteByte(0x11); o.WriteByte(0); o.WriteByte(0);
            return o.ToArray();
        }

        static void EmitLiterals(MemoryStream o, byte[] src, int start, int len, bool first)
        {
            if (len == 0) return;
            if (first && len <= 238)
            {
                o.WriteByte((byte)(17 + len));
            }
            else if (!first && len <= 3)
            {
                // short run: stored in the low two bits of the previous match instruction
                byte[] buf = o.GetBuffer();
                long pos = o.Length - 2;
                buf[pos] = (byte)(buf[pos] | len);
            }
            else if (len - 3 <= 15)
            {
                o.WriteByte((byte)(len - 3));
            }
            else
            {
                o.WriteByte(0);
                int r = len - 3 - 15;
                while (r > 255) { o.WriteByte(0); r -= 255; }
                o.WriteByte((byte)r);
            }
            o.Write(src, start, len);
        }

        // The last two bytes written by every match carry the "trailing literals" count in bits 0..1.
        static void EmitMatch(MemoryStream o, int dist, int len)
        {
            if (len >= 3 && len <= 8 && dist <= 0x0800)
            {
                // M2: 1 L L D D D S S  then H H H H H H H H ; dist-1 = H<<3 | DDD
                int d = dist - 1;
                o.WriteByte((byte)(((len - 1) << 5) | ((d & 7) << 2)));
                o.WriteByte((byte)(d >> 3));
            }
            else if (dist <= 0x4000)
            {
                // M3: 001LLLLL  then  DDDDDDSS DDDDDDDD ; dist-1
                int d = dist - 1;
                int l = len - 2;
                if (l <= 31) o.WriteByte((byte)(0x20 | l));
                else
                {
                    o.WriteByte(0x20);
                    int r = l - 31;
                    while (r > 255) { o.WriteByte(0); r -= 255; }
                    o.WriteByte((byte)r);
                }
                o.WriteByte((byte)((d & 63) << 2));
                o.WriteByte((byte)(d >> 6));
            }
            else
            {
                // M4: 0001HLLL  then  DDDDDDSS DDDDDDDD ; dist - 0x4000, H = bit 14
                int d = dist - 0x4000;
                int l = len - 2;
                int hbit = (d & 0x4000) >> 11;
                if (l <= 7) o.WriteByte((byte)(0x10 | hbit | l));
                else
                {
                    o.WriteByte((byte)(0x10 | hbit));
                    int r = l - 7;
                    while (r > 255) { o.WriteByte(0); r -= 255; }
                    o.WriteByte((byte)r);
                }
                o.WriteByte((byte)((d & 63) << 2));
                o.WriteByte((byte)((d >> 6) & 0xFF));
            }
        }
    }

    public static class Lcw
    {
        public static byte[] Decompress(byte[] src, int srcOff, int srcLen, int outLen)
        {
            byte[] d = new byte[outLen];
            int i = srcOff, dp = 0, end = srcOff + srcLen;
            while (i < end && dp < outLen)
            {
                int cmd = src[i++];
                if ((cmd & 0x80) == 0)
                {
                    int count = ((cmd & 0x70) >> 4) + 3;
                    int pos = ((cmd & 0x0F) << 8) | src[i++];
                    for (int k = 0; k < count; k++) { d[dp] = d[dp - pos]; dp++; }
                }
                else if ((cmd & 0x40) == 0)
                {
                    int count = cmd & 0x3F;
                    if (count == 0) break;
                    Array.Copy(src, i, d, dp, count); i += count; dp += count;
                }
                else
                {
                    int count = cmd & 0x3F;
                    if (count < 0x3E)
                    {
                        count += 3;
                        int pos = src[i] | (src[i + 1] << 8); i += 2;
                        for (int k = 0; k < count; k++) d[dp++] = d[pos + k];
                    }
                    else if (count == 0x3E)
                    {
                        count = src[i] | (src[i + 1] << 8); i += 2;
                        byte v = src[i++];
                        for (int k = 0; k < count; k++) d[dp++] = v;
                    }
                    else
                    {
                        count = src[i] | (src[i + 1] << 8); i += 2;
                        int pos = src[i] | (src[i + 1] << 8); i += 2;
                        for (int k = 0; k < count; k++) d[dp++] = d[pos + k];
                    }
                }
            }
            return d;
        }

        // Literals and fills (runs of the same byte) only; enough for overlay data, which is mostly 0xFF.
        public static byte[] Compress(byte[] src)
        {
            MemoryStream o = new MemoryStream();
            int i = 0, n = src.Length;
            while (i < n)
            {
                int run = 1;
                while (i + run < n && src[i + run] == src[i] && run < 0xFFFF) run++;
                if (run >= 8)
                {
                    o.WriteByte(0xFE); o.WriteByte((byte)(run & 0xFF)); o.WriteByte((byte)(run >> 8)); o.WriteByte(src[i]);
                    i += run;
                    continue;
                }
                // literal block up to 63 bytes, stop before a long run
                int start = i, len = 0;
                while (i < n && len < 63)
                {
                    int r = 1;
                    while (i + r < n && src[i + r] == src[i] && r < 8) r++;
                    if (r >= 8) break;
                    i++; len++;
                }
                if (len > 0) { o.WriteByte((byte)(0x80 | len)); o.Write(src, start, len); }
            }
            o.WriteByte(0x80);
            return o.ToArray();
        }
    }

    // The packed sections of a map ([IsoMapPack5], [OverlayPack], [OverlayDataPack], [PreviewPack]):
    // base64 of a list of chunks, each: ushort compressed size, ushort uncompressed size, data.
    public static class Pack
    {
        public static byte[] Decode(byte[] packed, bool lzo, int totalHint)
        {
            MemoryStream o = new MemoryStream(totalHint > 0 ? totalHint : 65536);
            int i = 0;
            while (i + 4 <= packed.Length)
            {
                int cs = packed[i] | (packed[i + 1] << 8);
                int us = packed[i + 2] | (packed[i + 3] << 8);
                i += 4;
                if (cs == 0 || i + cs > packed.Length) break;
                byte[] chunk = lzo ? Lzo.Decompress(packed, i, cs, us) : Lcw.Decompress(packed, i, cs, us);
                o.Write(chunk, 0, chunk.Length);
                i += cs;
            }
            return o.ToArray();
        }

        public static byte[] Encode(byte[] raw, bool lzo, int chunkSize)
        {
            MemoryStream o = new MemoryStream();
            for (int i = 0; i < raw.Length; i += chunkSize)
            {
                int len = Math.Min(chunkSize, raw.Length - i);
                byte[] part = new byte[len];
                Array.Copy(raw, i, part, 0, len);
                byte[] c = lzo ? Lzo.Compress(part) : Lcw.Compress(part);
                o.WriteByte((byte)(c.Length & 0xFF)); o.WriteByte((byte)(c.Length >> 8));
                o.WriteByte((byte)(len & 0xFF)); o.WriteByte((byte)(len >> 8));
                o.Write(c, 0, c.Length);
            }
            return o.ToArray();
        }

        // Joins the numbered lines of a section (1=..., 2=...) and decodes the base64.
        public static byte[] FromSection(IniSection s)
        {
            if (s == null) return null;
            StringBuilder sb = new StringBuilder();
            List<KeyValuePair<int, string>> lines = new List<KeyValuePair<int, string>>();
            foreach (KeyValuePair<string, string> kv in s.Pairs)
            {
                int k;
                if (int.TryParse(kv.Key, out k)) lines.Add(new KeyValuePair<int, string>(k, kv.Value));
            }
            lines.Sort(delegate(KeyValuePair<int, string> a, KeyValuePair<int, string> b) { return a.Key.CompareTo(b.Key); });
            foreach (KeyValuePair<int, string> kv in lines) sb.Append(kv.Value);
            return Convert.FromBase64String(sb.ToString());
        }

        public static void ToSection(IniSection s, byte[] packed)
        {
            s.Pairs.Clear();
            string b64 = Convert.ToBase64String(packed);
            int line = 1;
            for (int i = 0; i < b64.Length; i += 70)
                s.Pairs.Add(new KeyValuePair<string, string>((line++).ToString(), b64.Substring(i, Math.Min(70, b64.Length - i))));
        }
    }

    // ------------------------------------------------------------------------------------------------
    // INI files (order-preserving; duplicate keys kept, as the game reads the first one)
    // ------------------------------------------------------------------------------------------------
    public sealed class IniSection
    {
        public string Name;
        public readonly List<KeyValuePair<string, string>> Pairs = new List<KeyValuePair<string, string>>();

        public string Get(string key)
        {
            foreach (KeyValuePair<string, string> kv in Pairs)
                if (string.Equals(kv.Key, key, StringComparison.OrdinalIgnoreCase)) return kv.Value;
            return null;
        }

        public void Set(string key, string value)
        {
            for (int i = 0; i < Pairs.Count; i++)
                if (string.Equals(Pairs[i].Key, key, StringComparison.OrdinalIgnoreCase))
                { Pairs[i] = new KeyValuePair<string, string>(Pairs[i].Key, value); return; }
            Pairs.Add(new KeyValuePair<string, string>(key, value));
        }

        public bool Remove(string key)
        {
            for (int i = 0; i < Pairs.Count; i++)
                if (string.Equals(Pairs[i].Key, key, StringComparison.OrdinalIgnoreCase)) { Pairs.RemoveAt(i); return true; }
            return false;
        }

        public List<string> Values()
        {
            List<string> r = new List<string>();
            foreach (KeyValuePair<string, string> kv in Pairs) r.Add(kv.Value);
            return r;
        }
    }

    public sealed class IniFile
    {
        public readonly List<IniSection> Sections = new List<IniSection>();
        readonly Dictionary<string, IniSection> index = new Dictionary<string, IniSection>(StringComparer.OrdinalIgnoreCase);

        public static Encoding Enc = Encoding.GetEncoding(1252);

        public static IniFile Parse(byte[] bytes) { return Parse(Enc.GetString(bytes)); }

        public static IniFile Parse(string text)
        {
            IniFile f = new IniFile();
            IniSection cur = null;
            using (StringReader r = new StringReader(text))
            {
                string line;
                while ((line = r.ReadLine()) != null)
                {
                    string l = line;
                    int sc = l.IndexOf(';');
                    if (sc >= 0) l = l.Substring(0, sc);
                    l = l.Trim();
                    if (l.Length == 0) continue;
                    if (l[0] == '[')
                    {
                        int e = l.IndexOf(']');
                        string name = e > 0 ? l.Substring(1, e - 1).Trim() : l.Substring(1).Trim();
                        cur = f.GetOrAdd(name);
                        continue;
                    }
                    if (cur == null) continue;
                    int eq = l.IndexOf('=');
                    if (eq <= 0) continue;
                    string k = l.Substring(0, eq).Trim();
                    string v = l.Substring(eq + 1).Trim();
                    // keep the first occurrence, like the game
                    if (cur.Get(k) == null) cur.Pairs.Add(new KeyValuePair<string, string>(k, v));
                }
            }
            return f;
        }

        public IniSection this[string name]
        {
            get { IniSection s; return index.TryGetValue(name, out s) ? s : null; }
        }

        public IniSection GetOrAdd(string name)
        {
            IniSection s;
            if (index.TryGetValue(name, out s)) return s;
            s = new IniSection(); s.Name = name;
            Sections.Add(s); index[name] = s;
            return s;
        }

        public bool RemoveSection(string name)
        {
            IniSection s;
            if (!index.TryGetValue(name, out s)) return false;
            Sections.Remove(s); index.Remove(name);
            return true;
        }

        public string Get(string section, string key)
        {
            IniSection s = this[section];
            return s == null ? null : s.Get(key);
        }

        public void Set(string section, string key, string value) { GetOrAdd(section).Set(key, value); }

        public string ToText()
        {
            StringBuilder sb = new StringBuilder();
            foreach (IniSection s in Sections)
            {
                sb.Append('[').Append(s.Name).Append("]\r\n");
                foreach (KeyValuePair<string, string> kv in s.Pairs) sb.Append(kv.Key).Append('=').Append(kv.Value).Append("\r\n");
                sb.Append("\r\n");
            }
            return sb.ToString();
        }

        public byte[] ToBytes() { return Enc.GetBytes(ToText()); }
    }
}
