// Lists all accesses to the given addresses (read/write, with function)
// and decompiles the accessing functions.
// Arguments: <outdir> <tag> <address> [<address> ...]
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
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.symbol.Reference;

public class TSXrefs extends GhidraScript {

    private static final int MAX_DECOMP = 60;

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        File outDir = new File(args[0]);
        String tag = args[1];
        File decompDir = new File(outDir, "decomp");
        decompDir.mkdirs();

        Map<Function, String> funcs = new LinkedHashMap<>();
        try (PrintWriter pw = new PrintWriter(new FileWriter(new File(outDir, "xrefs_" + tag + ".txt")))) {
            for (int i = 2; i < args.length; i++) {
                Address a = toAddr(args[i]);
                int reads = 0, writes = 0;
                Map<Function, int[]> perFunc = new LinkedHashMap<>();
                for (Reference r : getReferencesTo(a)) {
                    Function f = getFunctionContaining(r.getFromAddress());
                    boolean w = r.getReferenceType().isWrite();
                    if (w) writes++; else reads++;
                    if (f == null) continue;
                    int[] c = perFunc.computeIfAbsent(f, k -> new int[2]);
                    c[w ? 1 : 0]++;
                }
                pw.printf("%n%s: %d reads, %d writes, %d functions%n", a, reads, writes, perFunc.size());
                for (Map.Entry<Function, int[]> e : perFunc.entrySet()) {
                    Function f = e.getKey();
                    pw.printf("    %-16s @ %s  read %d  write %d  (%d bytes)%n", f.getName(), f.getEntryPoint(),
                        e.getValue()[0], e.getValue()[1], f.getBody().getNumAddresses());
                    funcs.merge(f, args[i], (x, y) -> x.contains(y) ? x : x + "," + y);
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
                pw.printf("// %s @ %s  (%d bytes)  accesses: %s%n", f.getName(), f.getEntryPoint(),
                    f.getBody().getNumAddresses(), e.getValue());
                pw.println(r.decompileCompleted() ? r.getDecompiledFunction().getC()
                    : "// Decompilation failed: " + r.getErrorMessage());
            }
        }
        decomp.dispose();
    }
}
