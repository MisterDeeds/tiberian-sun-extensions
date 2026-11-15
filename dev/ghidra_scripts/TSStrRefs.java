// Finds ASCII strings in the program, lists every instruction that references them and decompiles the
// referencing functions.
// Arguments: <outdir> <tag> <string> [<string> ...]   (exact string match, case-sensitive)
//@category TiberianSun

import java.io.File;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.util.*;

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.symbol.Reference;

public class TSStrRefs extends GhidraScript {

    private static final int MAX_DECOMP = 40;

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        File outDir = new File(args[0]);
        String tag = args[1];
        File decompDir = new File(outDir, "decomp");
        decompDir.mkdirs();
        Memory mem = currentProgram.getMemory();

        Map<Function, String> funcs = new LinkedHashMap<>();
        try (PrintWriter pw = new PrintWriter(new FileWriter(new File(outDir, "strrefs_" + tag + ".txt")))) {
            for (int i = 2; i < args.length; i++) {
                byte[] pat = (args[i] + "\0").getBytes("ISO-8859-1");
                Address start = currentProgram.getMinAddress();
                while (start != null) {
                    Address hit = mem.findBytes(start, pat, null, true, monitor);
                    if (hit == null) break;
                    pw.printf("%n\"%s\" @ %s%n", args[i], hit);
                    for (Reference r : getReferencesTo(hit)) {
                        Function f = getFunctionContaining(r.getFromAddress());
                        pw.printf("    ref %s in %s%n", r.getFromAddress(), f == null ? "?" : f.getName() + " @ " + f.getEntryPoint());
                        if (f != null) funcs.merge(f, args[i], (x, y) -> x.contains(y) ? x : x + "," + y);
                    }
                    // Also raw 4-byte pointer occurrences (tables of string pointers)
                    long v = hit.getOffset();
                    byte[] ptr = new byte[] { (byte) v, (byte) (v >> 8), (byte) (v >> 16), (byte) (v >> 24) };
                    Address ps = currentProgram.getMinAddress();
                    int n = 0;
                    while (ps != null && n < 20) {
                        Address ph = mem.findBytes(ps, ptr, null, true, monitor);
                        if (ph == null) break;
                        pw.printf("    ptr %s%n", ph);
                        ps = ph.add(1);
                        n++;
                    }
                    start = hit.add(1);
                }
            }
            pw.printf("%nDifferent functions in total: %d%n", funcs.size());
        }

        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(currentProgram);
        int n = 0;
        for (Map.Entry<Function, String> e : funcs.entrySet()) {
            if (n++ >= MAX_DECOMP || monitor.isCancelled()) break;
            Function f = e.getKey();
            DecompileResults r = decomp.decompileFunction(f, 120, monitor);
            File out = new File(decompDir, tag + "_" + f.getEntryPoint() + ".c");
            try (PrintWriter pw = new PrintWriter(new FileWriter(out))) {
                pw.printf("// %s @ %s  (%d bytes)  strings: %s%n", f.getName(), f.getEntryPoint(),
                    f.getBody().getNumAddresses(), e.getValue());
                pw.println(r.decompileCompleted() ? r.getDecompiledFunction().getC()
                    : "// Decompilation failed: " + r.getErrorMessage());
            }
        }
        decomp.dispose();
    }
}
